import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_token_store.dart';

void main() {
  test(
    'stores a pair as one versioned envelope and redacts diagnostics',
    () async {
      final storage = _MemorySecureValueStore();
      final store = SecureAuthTokenStore(storage: storage);
      final pair = AuthTokenPair(
        accessToken: 'sensitive-access',
        refreshToken: 'sensitive-refresh',
      );

      final snapshot = await store.write(pair);

      expect(storage.values.keys, <String>[SecureAuthTokenStore.storageKey]);
      final envelope = jsonDecode(storage.values.values.single);
      expect(envelope['version'], 1);
      expect(envelope['accessToken'], 'sensitive-access');
      expect(envelope['refreshToken'], 'sensitive-refresh');
      expect(pair.toString(), isNot(contains('sensitive-access')));
      expect(snapshot.toString(), isNot(contains('sensitive-refresh')));
    },
  );

  test('serializes CAS so exactly one rotation can win', () async {
    final store = SecureAuthTokenStore(storage: _MemorySecureValueStore());
    final initial = await store.write(
      AuthTokenPair(accessToken: 'access-a', refreshToken: 'refresh-a'),
    );

    final rotations = await Future.wait(<Future<AuthCredentialSnapshot?>>[
      store.compareAndSet(
        expectedRevision: initial.revision,
        replacement: AuthTokenPair(
          accessToken: 'access-b',
          refreshToken: 'refresh-b',
        ),
      ),
      store.compareAndSet(
        expectedRevision: initial.revision,
        replacement: AuthTokenPair(
          accessToken: 'access-c',
          refreshToken: 'refresh-c',
        ),
      ),
    ]);

    expect(rotations.whereType<AuthCredentialSnapshot>(), hasLength(1));
    expect(rotations.where((item) => item == null), hasLength(1));
    expect((await store.read())?.revision, initial.revision + 1);
  });

  test('verifies writes and refuses to report a discarded write', () async {
    final storage = _MemorySecureValueStore()..discardNextWrite = true;
    final store = SecureAuthTokenStore(storage: storage);

    await expectLater(
      store.write(
        AuthTokenPair(accessToken: 'access-a', refreshToken: 'refresh-a'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await store.read(), isNull);
  });

  test('verifies deletion and remains retryable after failure', () async {
    final storage = _MemorySecureValueStore();
    final store = SecureAuthTokenStore(storage: storage);
    await store.write(
      AuthTokenPair(accessToken: 'access-a', refreshToken: 'refresh-a'),
    );
    storage.ignoreNextDelete = true;

    await expectLater(store.delete(), throwsA(isA<StateError>()));
    expect(await store.read(), isNotNull);

    await store.delete();
    await store.delete();
    expect(await store.read(), isNull);
  });

  test('fails closed for a malformed secure envelope', () async {
    final storage =
        _MemorySecureValueStore()
          ..values[SecureAuthTokenStore.storageKey] =
              '{"accessToken":"secret"}';
    final store = SecureAuthTokenStore(storage: storage);

    await expectLater(
      store.read(),
      throwsA(isA<CredentialStoreCorruptedException>()),
    );
  });

  test('server verification uses revision CAS', () async {
    final store = SecureAuthTokenStore(storage: _MemorySecureValueStore());
    final migrated = await store.write(
      AuthTokenPair(accessToken: 'access-a', refreshToken: 'refresh-a'),
      requiresServerVerification: true,
    );

    expect(
      await store.markServerVerified(expectedRevision: migrated.revision + 1),
      isNull,
    );
    final verified = await store.markServerVerified(
      expectedRevision: migrated.revision,
    );
    expect(verified?.requiresServerVerification, isFalse);
    expect(verified?.revision, migrated.revision);
  });
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  bool discardNextWrite = false;
  bool ignoreNextDelete = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (discardNextWrite) {
      discardNextWrite = false;
      return;
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (ignoreNextDelete) {
      ignoreNextDelete = false;
      return;
    }
    values.remove(key);
  }
}
