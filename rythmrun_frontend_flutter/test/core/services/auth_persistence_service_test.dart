import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_persistence_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_token_store.dart';
import 'package:rythmrun_frontend_flutter/data/models/auth_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/models/user_model.dart';

void main() {
  // Keep test JWT expiry independent of the host clock used by jwt_decoder.
  final now = DateTime.utc(2035, 7, 13, 12);

  AuthPersistenceService service({
    required _MemorySecureValueStore secure,
    required _MemoryPreferences preferences,
  }) {
    return AuthPersistenceService(
      // The store shares the service clock so its stamped verified/observed
      // timestamps and the offline-window policy agree under the fake clock.
      tokenStore: SecureAuthTokenStore(storage: secure, now: () => now),
      preferencesFactory: () async => preferences,
      now: () => now,
    );
  }

  test('migrates one coherent IP-2.1 pair and removes plaintext', () async {
    final secure = _MemorySecureValueStore();
    final pair = _ip21Pair(now);
    final preferences = _MemoryPreferences(<String, Object>{
      AuthPersistenceService.legacyAccessTokenKey: pair.accessToken,
      AuthPersistenceService.legacyRefreshTokenKey: pair.refreshToken,
      AuthPersistenceService.userDataKey: _encodedUser,
      AuthPersistenceService.lastBackendSyncKey:
          now.subtract(const Duration(hours: 1)).toIso8601String(),
    });

    final snapshot =
        await service(
          secure: secure,
          preferences: preferences,
        ).readCredentialSnapshot();

    expect(snapshot?.pair, pair);
    expect(snapshot?.requiresServerVerification, isTrue);
    expect(preferences.containsKey('access_token'), isFalse);
    expect(preferences.containsKey('refresh_token'), isFalse);
    expect(preferences.containsKey('user_data'), isTrue);
    expect(preferences.containsKey('last_backend_sync'), isTrue);
    expect(secure.writeCount, 1);
  });

  test('retains plaintext when the secure write is interrupted', () async {
    final secure = _MemorySecureValueStore()..throwAfterNextWrite = true;
    final pair = _ip21Pair(now);
    final preferences = _MemoryPreferences(<String, Object>{
      'access_token': pair.accessToken,
      'refresh_token': pair.refreshToken,
      'user_data': _encodedUser,
    });
    final persistence = service(secure: secure, preferences: preferences);

    await expectLater(
      persistence.readCredentialSnapshot(),
      throwsA(isA<StateError>()),
    );
    expect(preferences.containsKey('access_token'), isTrue);
    expect(preferences.containsKey('refresh_token'), isTrue);

    // The write committed before interruption. A retry treats the read-back
    // secure envelope as authoritative and finishes plaintext cleanup.
    final recovered = await persistence.readCredentialSnapshot();
    expect(recovered?.pair, pair);
    expect(preferences.containsKey('access_token'), isFalse);
    expect(preferences.containsKey('refresh_token'), isFalse);
  });

  test(
    'resumes after interruption while removing legacy preferences',
    () async {
      final secure = _MemorySecureValueStore();
      final pair = _ip21Pair(now);
      final preferences = _MemoryPreferences(<String, Object>{
        'access_token': pair.accessToken,
        'refresh_token': pair.refreshToken,
        'user_data': _encodedUser,
      })..failNextRemoveFor('refresh_token');
      final persistence = service(secure: secure, preferences: preferences);

      await expectLater(
        persistence.readCredentialSnapshot(),
        throwsA(isA<StateError>()),
      );
      expect(preferences.containsKey('access_token'), isFalse);
      expect(preferences.containsKey('refresh_token'), isTrue);

      final recovered = await persistence.readCredentialSnapshot();
      expect(recovered?.pair, pair);
      expect(preferences.containsKey('refresh_token'), isFalse);
      expect(secure.writeCount, 1);
    },
  );

  test('existing secure credentials win over stale preferences', () async {
    final secure = _MemorySecureValueStore();
    final tokenStore = SecureAuthTokenStore(storage: secure, now: () => now);
    final securePair = AuthTokenPair(
      accessToken: 'secure-access',
      refreshToken: 'secure-refresh',
    );
    await tokenStore.write(securePair);
    final legacyPair = _ip21Pair(now);
    final preferences = _MemoryPreferences(<String, Object>{
      'access_token': legacyPair.accessToken,
      'refresh_token': legacyPair.refreshToken,
    });
    final persistence = AuthPersistenceService(
      tokenStore: tokenStore,
      preferencesFactory: () async => preferences,
      now: () => now,
    );

    final snapshot = await persistence.readCredentialSnapshot();

    expect(snapshot?.pair, securePair);
    expect(preferences.containsKey('access_token'), isFalse);
    expect(preferences.containsKey('refresh_token'), isFalse);
  });

  test('coalesces concurrent migration reads into one secure write', () async {
    final secure = _MemorySecureValueStore();
    final pair = _ip21Pair(now);
    final preferences = _MemoryPreferences(<String, Object>{
      'access_token': pair.accessToken,
      'refresh_token': pair.refreshToken,
      'user_data': _encodedUser,
    });
    final persistence = service(secure: secure, preferences: preferences);

    final snapshots = await Future.wait(
      List<Future<AuthCredentialSnapshot?>>.generate(
        24,
        (_) => persistence.readCredentialSnapshot(),
      ),
    );

    expect(snapshots, everyElement(isNotNull));
    expect(snapshots.map((item) => item!.revision).toSet(), hasLength(1));
    expect(secure.writeCount, 1);
  });

  test('rejects and removes incomplete or non-IP-2.1 legacy pairs', () async {
    for (final values in <Map<String, Object>>[
      <String, Object>{'access_token': 'legacy-access-only'},
      <String, Object>{
        'access_token': 'pre-session-access',
        'refresh_token': 'pre-session-refresh',
      },
      <String, Object>{
        'access_token': _ip21Pair(now).accessToken,
        'refresh_token':
            _ip21Pair(
              now,
              sessionId: '99999999-9999-4999-8999-999999999999',
            ).refreshToken,
      },
    ]) {
      final secure = _MemorySecureValueStore();
      final preferences = _MemoryPreferences(values);

      expect(
        await service(
          secure: secure,
          preferences: preferences,
        ).readCredentialSnapshot(),
        isNull,
      );
      expect(preferences.containsKey('access_token'), isFalse);
      expect(preferences.containsKey('refresh_token'), isFalse);
      expect(secure.values, isEmpty);
    }
  });

  test('rejects a legacy pair belonging to another stored user', () async {
    final secure = _MemorySecureValueStore();
    final pair = _ip21Pair(now, subject: '8');
    final preferences = _MemoryPreferences(<String, Object>{
      'access_token': pair.accessToken,
      'refresh_token': pair.refreshToken,
      'user_data': _encodedUser,
    });

    expect(
      await service(
        secure: secure,
        preferences: preferences,
      ).readCredentialSnapshot(),
      isNull,
    );
    expect(secure.values, isEmpty);
  });

  test(
    'fresh authentication never stores credentials in preferences',
    () async {
      final secure = _MemorySecureValueStore();
      final preferences = _MemoryPreferences();
      final persistence = service(secure: secure, preferences: preferences);

      await persistence.saveAuthData(
        const AuthResponseModel(
          user: UserModel(
            id: '7',
            firstName: 'Test',
            lastName: 'Runner',
            email: 'runner@example.test',
          ),
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
        ),
      );

      expect(preferences.containsKey('access_token'), isFalse);
      expect(preferences.containsKey('refresh_token'), isFalse);
      expect(preferences.containsKey('user_data'), isTrue);
      expect(preferences.containsKey('last_backend_sync'), isTrue);
      expect(
        (await persistence.readCredentialSnapshot())?.pair.accessToken,
        'new-access',
      );
    },
  );

  test('cleanup marker remains until every account value is absent', () async {
    final secure = _MemorySecureValueStore();
    final preferences = _MemoryPreferences();
    final persistence = service(secure: secure, preferences: preferences);
    await persistence.saveAuthData(
      const AuthResponseModel(
        user: UserModel(
          id: '7',
          firstName: 'Test',
          lastName: 'Runner',
          email: 'runner@example.test',
        ),
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
      ),
    );
    await persistence.markAuthCleanupPending();
    preferences.failNextRemoveFor('user_data');

    await expectLater(persistence.clearAuthData(), throwsA(isA<StateError>()));
    expect(await persistence.hasPendingAuthCleanup(), isTrue);
    expect(await persistence.readCredentialSnapshot(), isNull);

    await persistence.clearAuthData();
    await persistence.clearAuthData();
    expect(await persistence.hasPendingAuthCleanup(), isFalse);
    expect(preferences.containsKey('user_data'), isFalse);
    expect(preferences.containsKey('last_backend_sync'), isFalse);
    expect(secure.values, isEmpty);
  });

  test('migrated credentials are ineligible for offline admission', () async {
    final secure = _MemorySecureValueStore();
    final pair = _ip21Pair(now);
    final preferences = _MemoryPreferences(<String, Object>{
      'access_token': pair.accessToken,
      'refresh_token': pair.refreshToken,
      'user_data': _encodedUser,
      'last_backend_sync': now.toIso8601String(),
    });
    final persistence = service(secure: secure, preferences: preferences);

    final migrated = await persistence.readCredentialSnapshot();
    expect(await persistence.canStayLoggedInOffline(), isFalse);

    final verified = await persistence.markCredentialsServerVerified(
      expectedRevision: migrated!.revision,
    );
    expect(verified?.requiresServerVerification, isFalse);
    expect(await persistence.canStayLoggedInOffline(), isTrue);
  });

  test(
    'verified session stays offline-eligible when only access expired',
    () async {
      final offlineNow = DateTime.now().toUtc();
      final secure = _MemorySecureValueStore();
      final pair = _ip21Pair(offlineNow, accessExpired: true);
      final preferences = _MemoryPreferences(<String, Object>{
        'access_token': pair.accessToken,
        'refresh_token': pair.refreshToken,
        'user_data': _encodedUser,
        'last_backend_sync': offlineNow.toIso8601String(),
      });
      final persistence = AuthPersistenceService(
        tokenStore: SecureAuthTokenStore(
          storage: secure,
          now: () => offlineNow,
        ),
        preferencesFactory: () async => preferences,
        now: () => offlineNow,
      );

      final migrated = await persistence.readCredentialSnapshot();
      await persistence.markCredentialsServerVerified(
        expectedRevision: migrated!.revision,
      );

      expect(await persistence.hasValidSession(), isFalse);
      expect(await persistence.canStayLoggedInOffline(), isTrue);
    },
  );

  test(
    'credential cleanup is serialized after an in-flight migration',
    () async {
      final pair = _ip21Pair(now);
      final preferences = _MemoryPreferences(<String, Object>{
        'access_token': pair.accessToken,
        'refresh_token': pair.refreshToken,
        'user_data': _encodedUser,
        'last_backend_sync': now.toIso8601String(),
      });
      final tokenStore = _BlockingAuthTokenStore();
      final persistence = AuthPersistenceService(
        tokenStore: tokenStore,
        preferencesFactory: () async => preferences,
        now: () => now,
      );

      final migration = persistence.readCredentialSnapshot();
      await tokenStore.firstReadStarted.future;

      final cleanup = persistence.clearAuthData();
      await Future<void>.delayed(Duration.zero);
      expect(tokenStore.deleteCalls, 0);

      tokenStore.releaseFirstRead.complete();
      expect((await migration)?.pair, pair);
      await cleanup;

      expect(await tokenStore.read(), isNull);
      expect(tokenStore.deleteCalls, 1);
      expect(preferences.containsKey('access_token'), isFalse);
      expect(preferences.containsKey('refresh_token'), isFalse);
      expect(preferences.containsKey('user_data'), isFalse);
      expect(preferences.containsKey('last_backend_sync'), isFalse);
    },
  );
}

const String _encodedUser =
    '{"id":"7","firstName":"Test","lastName":"Runner",'
    '"email":"runner@example.test","profilePicturePath":null,'
    '"profilePictureType":null,"createdAt":null}';

AuthTokenPair _ip21Pair(
  DateTime now, {
  String subject = '7',
  String sessionId = '11111111-1111-4111-8111-111111111111',
  bool accessExpired = false,
}) {
  final issuedAt = now.millisecondsSinceEpoch ~/ 1000 - 60;
  return AuthTokenPair(
    accessToken: _jwt(<String, Object>{
      'sub': subject,
      'sid': sessionId,
      'jti': '22222222-2222-4222-8222-222222222222',
      'typ': 'access',
      'iat': issuedAt,
      'exp': accessExpired ? issuedAt + 30 : issuedAt + 15 * 60,
    }),
    refreshToken: _jwt(<String, Object>{
      'sub': subject,
      'sid': sessionId,
      'jti': '33333333-3333-4333-8333-333333333333',
      'typ': 'refresh',
      'iat': issuedAt,
      'exp': issuedAt + 7 * 24 * 60 * 60,
    }),
  );
}

String _jwt(Map<String, Object> claims) {
  String encode(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode(<String, Object>{'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode(claims)}.${encode('signature')}';
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  bool throwAfterNextWrite = false;
  int writeCount = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount += 1;
    values[key] = value;
    if (throwAfterNextWrite) {
      throwAfterNextWrite = false;
      throw StateError('Simulated secure write interruption.');
    }
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final class _BlockingAuthTokenStore implements AuthTokenStore {
  final Completer<void> firstReadStarted = Completer<void>();
  final Completer<void> releaseFirstRead = Completer<void>();
  AuthCredentialSnapshot? current;
  bool _didBlockRead = false;
  int deleteCalls = 0;

  @override
  Future<AuthCredentialSnapshot?> read() async {
    if (!_didBlockRead) {
      _didBlockRead = true;
      firstReadStarted.complete();
      await releaseFirstRead.future;
    }
    return current;
  }

  @override
  Future<AuthCredentialSnapshot> write(
    AuthTokenPair pair, {
    bool requiresServerVerification = false,
  }) async {
    current = AuthCredentialSnapshot(
      pair: pair,
      revision: (current?.revision ?? 0) + 1,
      requiresServerVerification: requiresServerVerification,
    );
    return current!;
  }

  @override
  Future<AuthCredentialSnapshot?> compareAndSet({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  }) async {
    if (current?.revision != expectedRevision) return null;
    return write(
      replacement,
      requiresServerVerification: requiresServerVerification,
    );
  }

  @override
  Future<AuthCredentialSnapshot?> markServerVerified({
    required int expectedRevision,
  }) async {
    final existing = current;
    if (existing == null || existing.revision != expectedRevision) return null;
    current = AuthCredentialSnapshot(
      pair: existing.pair,
      revision: existing.revision,
      requiresServerVerification: false,
    );
    return current;
  }

  @override
  Future<AuthCredentialSnapshot?> advanceObservedClock() async => current;

  @override
  Future<void> delete() async {
    deleteCalls++;
    current = null;
  }

  @override
  Future<bool> deleteIfRevision(int expectedRevision) async {
    final existing = current;
    if (existing == null) return true;
    if (existing.revision != expectedRevision) return false;
    await delete();
    return true;
  }
}

final class _MemoryPreferences implements AuthPreferences {
  _MemoryPreferences([Map<String, Object>? initial])
    : values = <String, Object>{...?initial};

  final Map<String, Object> values;
  final Set<String> _failNextRemove = <String>{};

  void failNextRemoveFor(String key) => _failNextRemove.add(key);

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> remove(String key) async {
    if (_failNextRemove.remove(key)) return false;
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}
