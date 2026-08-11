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
            hasPassword: false,
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
      expect((await persistence.getUserData())?.hasPassword, isFalse);
    },
  );

  test('older cached users default to password-capable', () async {
    final persistence = service(
      secure: _MemorySecureValueStore(),
      preferences: _MemoryPreferences(<String, Object>{
        AuthPersistenceService.userDataKey: _encodedUser,
      }),
    );

    expect((await persistence.getUserData())?.hasPassword, isTrue);
  });

  test('older cached users default to email-verified', () async {
    final persistence = service(
      secure: _MemorySecureValueStore(),
      preferences: _MemoryPreferences(<String, Object>{
        AuthPersistenceService.userDataKey: _encodedUser,
      }),
    );

    // A blob cached before the field existed must not look unverified.
    expect((await persistence.getUserData())?.emailVerified, isTrue);
  });

  test('locally rewritten users keep an unverified email flag', () async {
    final persistence = service(
      secure: _MemorySecureValueStore(),
      preferences: _MemoryPreferences(),
    );

    await persistence.updateUserData(
      const UserModel(
        id: '7',
        firstName: 'Ada',
        lastName: 'Runner',
        email: 'runner@example.test',
        emailVerified: false,
      ),
    );

    // updateUserData/getUserData hand-roll their JSON instead of going through
    // UserModel, so this guards against silently dropping the field.
    expect((await persistence.getUserData())?.emailVerified, isFalse);
  });

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

      // A direct write stamps the pair as verified now, so the only reason it
      // is not a valid online session is the expired access token.
      await persistence.replaceCredentials(pair);

      expect(await persistence.hasValidSession(), isFalse);
      expect(await persistence.canStayLoggedInOffline(), isTrue);
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
