import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_persistence_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_token_store.dart';

/// IP-2.3 offline-session admission: the seven-day window is measured against
/// an integrity-sensitive verification timestamp in the secure envelope, with
/// clock-rollback and future-timestamp tamper checks that fail closed. A fake
/// clock drives every boundary; JWT expiry stays in the real future so only the
/// verification window governs the outcome.
void main() {
  // A base wall clock far enough ahead that the pair's own real-time JWT expiry
  // never trips jwt_decoder during these tests.
  final base = DateTime.utc(2035, 1, 1, 12);

  ({
    AuthPersistenceService service,
    _MemorySecureValueStore secure,
    _MemoryPreferences preferences,
    void Function(DateTime) setNow,
  })
  build({Map<String, Object>? preferences}) {
    var current = base;
    final secure = _MemorySecureValueStore();
    final prefs = _MemoryPreferences(preferences);
    final service = AuthPersistenceService(
      tokenStore: SecureAuthTokenStore(storage: secure, now: () => current),
      preferencesFactory: () async => prefs,
      now: () => current,
    );
    return (
      service: service,
      secure: secure,
      preferences: prefs,
      setNow: (value) => current = value,
    );
  }

  group('verified offline window boundary', () {
    test('is eligible up to and at seven days and not after', () async {
      final harness = build(
        preferences: <String, Object>{
          AuthPersistenceService.userDataKey: _encodedUser,
        },
      );
      // A direct credential write anchors the verification time at [base].
      await harness.service.replaceCredentials(_pair(base));

      harness.setNow(
        base.add(const Duration(days: 7) - const Duration(seconds: 1)),
      );
      expect(await harness.service.canStayLoggedInOffline(), isTrue);

      harness.setNow(base.add(const Duration(days: 7)));
      expect(await harness.service.canStayLoggedInOffline(), isTrue);

      harness.setNow(
        base.add(const Duration(days: 7) + const Duration(seconds: 1)),
      );
      expect(await harness.service.canStayLoggedInOffline(), isFalse);
    });

    test('a window-exceeded pair never deletes cached data', () async {
      final harness = build(
        preferences: <String, Object>{
          AuthPersistenceService.userDataKey: _encodedUser,
        },
      );
      await harness.service.replaceCredentials(_pair(base));

      harness.setNow(base.add(const Duration(days: 30)));
      expect(await harness.service.canStayLoggedInOffline(), isFalse);
      // Fail-closed admission must not clear the credential or the cached user.
      expect(await harness.service.readCredentialSnapshot(), isNotNull);
      expect(await harness.service.getUserData(), isNotNull);
    });
  });

  group('clock tamper fails closed', () {
    test('rollback below the observed high-water is rejected', () async {
      final harness = build(
        preferences: <String, Object>{
          AuthPersistenceService.userDataKey: _encodedUser,
        },
      );
      await harness.service.replaceCredentials(_pair(base));

      // A legitimate later observation raises the high-water mark.
      harness.setNow(base.add(const Duration(days: 1)));
      expect(await harness.service.canStayLoggedInOffline(), isTrue);

      // Rolling the clock back below the high-water mark (still nominally inside
      // the window) must fail closed rather than extend offline access.
      harness.setNow(base.add(const Duration(hours: 12)));
      expect(await harness.service.canStayLoggedInOffline(), isFalse);

      // Rolling back before the verification instant also fails closed.
      harness.setNow(base.subtract(const Duration(hours: 1)));
      expect(await harness.service.canStayLoggedInOffline(), isFalse);
    });

    test('the rollback tripwire survives a process restart', () async {
      final secure = _MemorySecureValueStore();
      final prefs = _MemoryPreferences(<String, Object>{
        AuthPersistenceService.userDataKey: _encodedUser,
      });
      var first = base;
      final before = AuthPersistenceService(
        tokenStore: SecureAuthTokenStore(storage: secure, now: () => first),
        preferencesFactory: () async => prefs,
        now: () => first,
      );
      await before.replaceCredentials(_pair(base));
      first = base.add(const Duration(days: 2));
      expect(await before.canStayLoggedInOffline(), isTrue);

      // A fresh service over the same secure store models a process restart with
      // the clock rolled back below the persisted high-water mark.
      var second = base.add(const Duration(days: 1));
      final after = AuthPersistenceService(
        tokenStore: SecureAuthTokenStore(storage: secure, now: () => second),
        preferencesFactory: () async => prefs,
        now: () => second,
      );
      expect(await after.canStayLoggedInOffline(), isFalse);
      // Advancing forward again past the window is still bounded, not extended.
      second = base.add(const Duration(days: 8));
      expect(await after.canStayLoggedInOffline(), isFalse);
    });

    test('a future-dated verification cannot grant offline access', () async {
      final harness = build(
        preferences: <String, Object>{
          AuthPersistenceService.userDataKey: _encodedUser,
        },
      );
      // Seed a raw envelope whose verification time is far in the future and
      // whose observed high-water is absent, isolating the future-time guard.
      final pair = _pair(base);
      harness.secure.values[SecureAuthTokenStore
          .storageKey] = jsonEncode(<String, Object>{
        'version': 1,
        'revision': 1,
        'requiresServerVerification': false,
        'accessToken': pair.accessToken,
        'refreshToken': pair.refreshToken,
        'lastVerifiedAtMs':
            base.add(const Duration(days: 30)).millisecondsSinceEpoch,
      });

      harness.setNow(base);
      expect(await harness.service.canStayLoggedInOffline(), isFalse);
    });
  });

  group('trusted verification re-anchors and advance is best effort', () {
    test(
      'a forward clock excursion is recovered by online re-verification',
      () async {
        final harness = build(
          preferences: <String, Object>{
            AuthPersistenceService.userDataKey: _encodedUser,
          },
        );
        final anchored = await harness.service.replaceCredentials(_pair(base));

        // A transient forward clock excursion ratchets the observed high-water
        // mark far into the future while the pair is (now) window-expired.
        harness.setNow(base.add(const Duration(days: 100)));
        expect(await harness.service.canStayLoggedInOffline(), isFalse);

        // The clock is corrected. Without re-anchoring, the poisoned mark would
        // read as a permanent rollback; a trusted refresh must restore offline
        // eligibility rather than require a full logout/login.
        harness.setNow(base.add(const Duration(days: 1)));
        await harness.service.compareAndSetCredentials(
          expectedRevision: anchored.revision,
          replacement: _pair(
            base,
            sessionId: '11111111-1111-4111-8111-111111111111',
          ),
        );
        expect(await harness.service.canStayLoggedInOffline(), isTrue);
      },
    );

    test(
      'a failed observed-clock write never discards offline eligibility',
      () async {
        final harness = build(
          preferences: <String, Object>{
            AuthPersistenceService.userDataKey: _encodedUser,
          },
        );
        await harness.service.replaceCredentials(_pair(base));

        // The eligibility read succeeds but persisting the advanced high-water
        // mark fails transiently; admission must still be granted, not thrown.
        harness.setNow(base.add(const Duration(hours: 1)));
        harness.secure.failNextWrite = true;
        expect(await harness.service.canStayLoggedInOffline(), isTrue);
      },
    );
  });

  group('offline admission requires the secure credential', () {
    test(
      'cleared secure storage cannot authorize from cached prefs alone',
      () async {
        // Reinstall/clear leaves no secure envelope. Cached non-secret user
        // metadata (and any local SQLite rows keyed to it) must not be able to
        // infer offline authorization on their own.
        final harness = build(
          preferences: <String, Object>{
            AuthPersistenceService.userDataKey: _encodedUser,
            AuthPersistenceService.lastBackendSyncKey: base.toIso8601String(),
          },
        );

        expect(harness.secure.values.isEmpty, isTrue);
        expect(await harness.service.getUserData(), isNotNull);
        expect(await harness.service.canStayLoggedInOffline(), isFalse);
      },
    );

  });
}

const String _encodedUser =
    '{"id":"7","firstName":"Test","lastName":"Runner",'
    '"email":"runner@example.test","profilePicturePath":null,'
    '"profilePictureType":null,"createdAt":null}';

AuthTokenPair _pair(
  DateTime base, {
  String subject = '7',
  String sessionId = '11111111-1111-4111-8111-111111111111',
}) {
  final issuedAt = base.millisecondsSinceEpoch ~/ 1000 - 60;
  return AuthTokenPair(
    accessToken: _jwt(<String, Object>{
      'sub': subject,
      'sid': sessionId,
      'jti': '22222222-2222-4222-8222-222222222222',
      'typ': 'access',
      'iat': issuedAt,
      'exp': issuedAt + 15 * 60,
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
  bool failNextWrite = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Simulated transient secure write failure.');
    }
    values[key] = value;
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

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> remove(String key) async {
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
