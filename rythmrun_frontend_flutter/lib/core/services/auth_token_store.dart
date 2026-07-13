import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An access/refresh credential pair.
///
/// The pair deliberately has no JSON API and its string representation is
/// redacted so credentials cannot be included accidentally in diagnostics.
final class AuthTokenPair {
  AuthTokenPair({required this.accessToken, required this.refreshToken}) {
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw ArgumentError('Authentication credentials must not be empty.');
    }
  }

  final String accessToken;
  final String refreshToken;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AuthTokenPair &&
            other.accessToken == accessToken &&
            other.refreshToken == refreshToken;
  }

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);

  @override
  String toString() => 'AuthTokenPair(<redacted>)';
}

/// A coherent credential snapshot read from the secure store.
///
/// [revision] is an opaque compare-and-set generation for refresh rotation.
/// A migrated legacy pair requires a backend check before it is eligible for
/// normal offline admission.
final class AuthCredentialSnapshot {
  const AuthCredentialSnapshot({
    required this.pair,
    required this.revision,
    required this.requiresServerVerification,
  });

  final AuthTokenPair pair;
  final int revision;
  final bool requiresServerVerification;

  @override
  String toString() {
    return 'AuthCredentialSnapshot('
        'revision: $revision, '
        'requiresServerVerification: $requiresServerVerification, '
        'credentials: <redacted>)';
  }
}

/// The narrow credential contract consumed by authenticated networking.
abstract interface class AuthCredentialVault {
  Future<AuthCredentialSnapshot?> readCredentialSnapshot();

  /// Replaces a pair only when the current revision still matches.
  ///
  /// Returns `null` when another authentication operation won the race.
  Future<AuthCredentialSnapshot?> compareAndSetCredentials({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  });

  Future<AuthCredentialSnapshot?> markCredentialsServerVerified({
    required int expectedRevision,
  });
}

/// Removes only the credential generation that the backend has rejected.
///
/// The compare-and-delete contract prevents a delayed rejection from clearing a
/// newer login or refresh. If secure deletion is unavailable, the durable
/// cleanup marker keeps the cached account fail-closed across process restart.
abstract interface class RejectedCredentialQuarantine {
  Future<bool> clearCredentialsIfRevision(int expectedRevision);

  Future<void> markAuthCleanupPending();
}

/// Atomic, secure persistence for a single credential-pair envelope.
abstract interface class AuthTokenStore {
  Future<AuthCredentialSnapshot?> read();

  Future<AuthCredentialSnapshot> write(
    AuthTokenPair pair, {
    bool requiresServerVerification = false,
  });

  Future<AuthCredentialSnapshot?> compareAndSet({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  });

  Future<AuthCredentialSnapshot?> markServerVerified({
    required int expectedRevision,
  });

  Future<void> delete();

  Future<bool> deleteIfRevision(int expectedRevision);
}

/// Minimal key/value seam used to host-test secure-store interruption cases.
abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'rythmrun_auth_secure_v1',
              resetOnError: false,
              migrateOnAlgorithmChange: true,
              migrateWithBackup: true,
            ),
            iOptions: IOSOptions(
              accountName: 'com.github.cosmicsaurabh.rythmrun.auth.v1',
              accessibility: KeychainAccessibility.unlocked_this_device,
              synchronizable: false,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final class CredentialStoreCorruptedException implements Exception {
  const CredentialStoreCorruptedException();

  @override
  String toString() => 'The secure credential store is unreadable.';
}

/// Stores both credentials in one versioned JSON value.
///
/// Operations are serialized so compare-and-set is deterministic within the
/// application's single injected store. Every write/delete is read back before
/// it is reported as successful.
final class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({SecureValueStore? storage})
    : _storage = storage ?? FlutterSecureValueStore();

  static const String storageKey = 'credential_pair_envelope_v1';
  static const int _envelopeVersion = 1;

  final SecureValueStore _storage;
  Future<void> _operationTail = Future<void>.value();
  int _highestObservedRevision = 0;

  @override
  Future<AuthCredentialSnapshot?> read() {
    return _exclusive(_readUnsafe);
  }

  @override
  Future<AuthCredentialSnapshot> write(
    AuthTokenPair pair, {
    bool requiresServerVerification = false,
  }) {
    return _exclusive(() async {
      final current = await _readUnsafe();
      return _writeUnsafe(
        pair,
        revision: _nextRevision(current),
        requiresServerVerification: requiresServerVerification,
      );
    });
  }

  @override
  Future<AuthCredentialSnapshot?> compareAndSet({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  }) {
    return _exclusive(() async {
      final current = await _readUnsafe();
      if (current?.revision != expectedRevision) return null;

      return _writeUnsafe(
        replacement,
        revision: _nextRevision(current),
        requiresServerVerification: requiresServerVerification,
      );
    });
  }

  @override
  Future<AuthCredentialSnapshot?> markServerVerified({
    required int expectedRevision,
  }) {
    return _exclusive(() async {
      final current = await _readUnsafe();
      if (current?.revision != expectedRevision) return null;
      if (!current!.requiresServerVerification) return current;

      return _writeUnsafe(
        current.pair,
        // Revision identifies the credential pair, not envelope metadata. A
        // verification-only write must not make an in-flight refresh CAS look
        // stale after the backend has already consumed its refresh token.
        revision: current.revision,
        requiresServerVerification: false,
      );
    });
  }

  @override
  Future<void> delete() {
    return _exclusive(() async {
      final current = await _readUnsafe();
      if (current == null) return;
      _highestObservedRevision = current.revision + 1;
      await _deleteAndConfirm();
    });
  }

  @override
  Future<bool> deleteIfRevision(int expectedRevision) {
    return _exclusive(() async {
      final current = await _readUnsafe();
      if (current == null) return true;
      if (current.revision != expectedRevision) return false;
      _highestObservedRevision = current.revision + 1;
      await _deleteAndConfirm();
      return true;
    });
  }

  Future<AuthCredentialSnapshot?> _readUnsafe() async {
    final encoded = await _storage.read(storageKey);
    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _envelopeVersion ||
          decoded['revision'] is! int ||
          decoded['requiresServerVerification'] is! bool ||
          decoded['accessToken'] is! String ||
          decoded['refreshToken'] is! String) {
        throw const CredentialStoreCorruptedException();
      }

      final revision = decoded['revision'] as int;
      if (revision <= 0) {
        throw const CredentialStoreCorruptedException();
      }
      final pair = AuthTokenPair(
        accessToken: decoded['accessToken'] as String,
        refreshToken: decoded['refreshToken'] as String,
      );
      if (revision > _highestObservedRevision) {
        _highestObservedRevision = revision;
      }
      return AuthCredentialSnapshot(
        pair: pair,
        revision: revision,
        requiresServerVerification:
            decoded['requiresServerVerification'] as bool,
      );
    } on CredentialStoreCorruptedException {
      rethrow;
    } catch (_) {
      throw const CredentialStoreCorruptedException();
    }
  }

  int _nextRevision(AuthCredentialSnapshot? current) {
    final currentRevision = current?.revision ?? 0;
    final baseline =
        currentRevision > _highestObservedRevision
            ? currentRevision
            : _highestObservedRevision;
    return baseline + 1;
  }

  Future<AuthCredentialSnapshot> _writeUnsafe(
    AuthTokenPair pair, {
    required int revision,
    required bool requiresServerVerification,
  }) async {
    final encoded = jsonEncode(<String, Object>{
      'version': _envelopeVersion,
      'revision': revision,
      'requiresServerVerification': requiresServerVerification,
      'accessToken': pair.accessToken,
      'refreshToken': pair.refreshToken,
    });
    await _storage.write(storageKey, encoded);
    final readBack = await _storage.read(storageKey);
    if (readBack != encoded) {
      throw StateError('Secure credential write could not be verified.');
    }
    _highestObservedRevision = revision;
    return AuthCredentialSnapshot(
      pair: pair,
      revision: revision,
      requiresServerVerification: requiresServerVerification,
    );
  }

  Future<void> _deleteAndConfirm() async {
    await _storage.delete(storageKey);
    if (await _storage.read(storageKey) != null) {
      throw StateError('Secure credential deletion could not be verified.');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
