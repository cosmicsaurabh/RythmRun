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
///
/// [lastVerifiedAtMs] and [maxObservedAtMs] are integrity-sensitive session
/// metadata used by the offline-admission policy (IP-2.3). They travel inside
/// the same secure envelope as the credentials, are never client-writable in
/// plaintext preferences, and default to `null` for an envelope written before
/// IP-2.3. `null` [lastVerifiedAtMs] means "never server-verified since IP-2.3"
/// and fails closed on offline admission until an online verification stamps it.
final class AuthCredentialSnapshot {
  const AuthCredentialSnapshot({
    required this.pair,
    required this.revision,
    this.lastVerifiedAtMs,
    this.maxObservedAtMs,
  });

  final AuthTokenPair pair;
  final int revision;

  /// Epoch milliseconds of the last successful server verification of this
  /// credential pair (login, refresh rotation, or `/me`). The offline window
  /// is measured from this value.
  final int? lastVerifiedAtMs;

  /// Highest wall-clock epoch milliseconds observed since the last trusted
  /// reference (login, refresh, or verification), which reset it to their
  /// instant. Untrusted offline observations only ratchet it upward. A later
  /// `now` below this mark is treated as clock rollback and fails offline
  /// admission closed; re-anchoring on verification keeps a benign forward
  /// excursion from poisoning it permanently.
  final int? maxObservedAtMs;

  @override
  String toString() {
    return 'AuthCredentialSnapshot('
        'revision: $revision, '
        'lastVerifiedAtMs: $lastVerifiedAtMs, '
        'maxObservedAtMs: $maxObservedAtMs, '
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

  Future<AuthCredentialSnapshot> write(AuthTokenPair pair);

  Future<AuthCredentialSnapshot?> compareAndSet({
    required int expectedRevision,
    required AuthTokenPair replacement,
  });

  /// Records the current wall clock as the observed high-water mark without
  /// changing the credential revision. Writes only when the clock advances so
  /// a rolled-back clock cannot lower the mark. Returns `null` when no envelope
  /// exists, otherwise the resulting snapshot.
  Future<AuthCredentialSnapshot?> advanceObservedClock();

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
  SecureAuthTokenStore({SecureValueStore? storage, DateTime Function()? now})
    : _storage = storage ?? FlutterSecureValueStore(),
      _now = now ?? DateTime.now;

  static const String storageKey = 'credential_pair_envelope_v1';
  static const int _envelopeVersion = 1;

  final SecureValueStore _storage;
  final DateTime Function() _now;
  Future<void> _operationTail = Future<void>.value();
  int _highestObservedRevision = 0;

  int _nowMs() => _now().millisecondsSinceEpoch;

  static int _advancedObserved(int? previous, int nowMs) {
    if (previous == null || nowMs > previous) return nowMs;
    return previous;
  }

  @override
  Future<AuthCredentialSnapshot?> read() {
    return _exclusive(_readUnsafe);
  }

  @override
  Future<AuthCredentialSnapshot> write(AuthTokenPair pair) {
    return _exclusive(() async {
      final current = await _readUnsafe();
      final nowMs = _nowMs();
      return _writeUnsafe(
        pair,
        revision: _nextRevision(current),
        // A fresh write is a direct backend authentication, so it anchors the
        // verified time. Establishing a new credential is also a trusted
        // reference point, so the observed high-water mark resets to now — this
        // prevents a prior forward clock excursion from permanently poisoning
        // the rollback tripwire.
        lastVerifiedAtMs: nowMs,
        maxObservedAtMs: nowMs,
      );
    });
  }

  @override
  Future<AuthCredentialSnapshot?> compareAndSet({
    required int expectedRevision,
    required AuthTokenPair replacement,
  }) {
    return _exclusive(() async {
      final current = await _readUnsafe();
      if (current?.revision != expectedRevision) return null;

      final nowMs = _nowMs();
      return _writeUnsafe(
        replacement,
        revision: _nextRevision(current),
        // A successful refresh rotation is a backend verification of identity,
        // so it re-anchors both the verified time and the trusted observed mark.
        lastVerifiedAtMs: nowMs,
        maxObservedAtMs: nowMs,
      );
    });
  }

  @override
  Future<AuthCredentialSnapshot?> advanceObservedClock() {
    return _exclusive(() async {
      final current = await _readUnsafe();
      if (current == null) return null;

      final advanced = _advancedObserved(current.maxObservedAtMs, _nowMs());
      if (advanced == current.maxObservedAtMs) return current;

      return _writeUnsafe(
        current.pair,
        revision: current.revision,
        lastVerifiedAtMs: current.lastVerifiedAtMs,
        maxObservedAtMs: advanced,
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
        // Session metadata is optional and forgiving: a value absent from a
        // pre-IP-2.3 envelope, or present but malformed, reads back as null.
        // That fails offline admission closed rather than corrupting the whole
        // envelope and discarding an otherwise valid credential pair.
        lastVerifiedAtMs: _readOptionalTimestamp(decoded['lastVerifiedAtMs']),
        maxObservedAtMs: _readOptionalTimestamp(decoded['maxObservedAtMs']),
      );
    } on CredentialStoreCorruptedException {
      rethrow;
    } catch (_) {
      throw const CredentialStoreCorruptedException();
    }
  }

  static int? _readOptionalTimestamp(Object? value) {
    return value is int && value > 0 ? value : null;
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
    required int? lastVerifiedAtMs,
    required int? maxObservedAtMs,
  }) async {
    final envelope = <String, Object>{
      'version': _envelopeVersion,
      'revision': revision,
      'accessToken': pair.accessToken,
      'refreshToken': pair.refreshToken,
    };
    if (lastVerifiedAtMs != null) {
      envelope['lastVerifiedAtMs'] = lastVerifiedAtMs;
    }
    if (maxObservedAtMs != null) {
      envelope['maxObservedAtMs'] = maxObservedAtMs;
    }
    final encoded = jsonEncode(envelope);
    await _storage.write(storageKey, encoded);
    final readBack = await _storage.read(storageKey);
    if (readBack != encoded) {
      throw StateError('Secure credential write could not be verified.');
    }
    _highestObservedRevision = revision;
    return AuthCredentialSnapshot(
      pair: pair,
      revision: revision,
      lastVerifiedAtMs: lastVerifiedAtMs,
      maxObservedAtMs: maxObservedAtMs,
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
