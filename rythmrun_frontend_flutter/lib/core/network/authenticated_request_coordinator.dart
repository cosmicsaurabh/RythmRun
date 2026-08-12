import 'dart:async';

import 'package:jwt_decoder/jwt_decoder.dart';

import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/models/auth_response_model.dart';
import '../services/auth_token_store.dart';
import '../services/authentication_attempt_gate.dart';
import '../services/session_invalidation_signal.dart';
import 'auth_failures.dart';
import 'http_client.dart';

enum AuthenticatedReplayPolicy { never, idempotent }

abstract interface class AuthenticatedRequestExecutor {
  Future<T> execute<T>({
    required Future<T> Function(Map<String, String> authHeaders) request,
    AuthenticatedReplayPolicy replayPolicy = AuthenticatedReplayPolicy.never,
  });
}

/// Owns authenticated headers and refresh rotation so repositories cannot send
/// requests with independently cached credentials.
class AuthenticatedRequestCoordinator implements AuthenticatedRequestExecutor {
  AuthenticatedRequestCoordinator({
    required AuthCredentialVault credentialVault,
    required RejectedCredentialQuarantine rejectedCredentialQuarantine,
    required AuthRemoteDataSource authRemoteDataSource,
    required AuthenticationAttemptGate authenticationAttemptGate,
    required SessionInvalidationSignal sessionInvalidationSignal,
    required Future<void> Function(AuthResponseModel response)
    commitRefreshedSession,
    required Future<void> Function() commitServerVerification,
  }) : _credentialVault = credentialVault,
       _rejectedCredentialQuarantine = rejectedCredentialQuarantine,
       _authRemoteDataSource = authRemoteDataSource,
       _authenticationAttemptGate = authenticationAttemptGate,
       _sessionInvalidationSignal = sessionInvalidationSignal,
       _commitRefreshedSession = commitRefreshedSession,
       _commitServerVerification = commitServerVerification;

  static const String invalidAccessCode = 'AUTH_ACCESS_INVALID';
  static const String invalidRefreshCode = 'AUTH_REFRESH_INVALID';

  final AuthCredentialVault _credentialVault;
  final RejectedCredentialQuarantine _rejectedCredentialQuarantine;
  final AuthRemoteDataSource _authRemoteDataSource;
  final AuthenticationAttemptGate _authenticationAttemptGate;
  final SessionInvalidationSignal _sessionInvalidationSignal;
  final Future<void> Function(AuthResponseModel response)
  _commitRefreshedSession;
  final Future<void> Function() _commitServerVerification;
  final Map<int, Future<_RefreshResult>> _refreshFlights =
      <int, Future<_RefreshResult>>{};
  final Map<int, int> _activeOperationsByRevision = <int, int>{};

  @override
  Future<T> execute<T>({
    required Future<T> Function(Map<String, String> authHeaders) request,
    AuthenticatedReplayPolicy replayPolicy = AuthenticatedReplayPolicy.never,
  }) async {
    final initial = await _readRequiredSnapshot();
    _beginOperation(initial.revision);

    try {
      try {
        final result = await request(_headersFor(initial));
        await _completeSuccessfulRequest(initial);
        return result;
      } on UnauthorizedException catch (error) {
        if (error.code != invalidAccessCode) rethrow;
      }

      final refreshed = await _refreshFor(initial);
      if (replayPolicy == AuthenticatedReplayPolicy.never) {
        throw const AuthSessionUnavailable(
          AuthSessionUnavailableReason.requestNotReplayed,
        );
      }

      await _requireCurrent(refreshed.snapshot);
      final result = await request(_headersFor(refreshed.snapshot));
      await _completeSuccessfulRequest(refreshed.snapshot);
      return result;
    } finally {
      _endOperation(initial.revision);
    }
  }

  /// Explicit refresh used by session startup. It shares the same in-flight
  /// rotation as protected requests and persists the pair before returning.
  Future<AuthResponseModel> refreshSession() async {
    final snapshot = await _readRequiredSnapshot();
    _beginOperation(snapshot.revision);
    try {
      final result = await _refreshFor(snapshot);
      return result.response;
    } finally {
      _endOperation(snapshot.revision);
    }
  }

  /// Runs a mutation whose successful backend commit revokes the current
  /// session, then removes that exact local credential revision before
  /// notifying the session coordinator. The mutation is never replayed.
  Future<T> executeSessionRevoking<T>({
    required Future<T> Function(Map<String, String> authHeaders) request,
    required SessionInvalidationReason reason,
  }) async {
    final lease = _authenticationAttemptGate.tryAcquire();
    if (lease == null) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.authenticationBusy,
      );
    }

    AuthCredentialSnapshot? initial;
    try {
      initial = await _readRequiredSnapshot();
      _beginOperation(initial.revision);

      late final T result;
      try {
        result = await request(_headersFor(initial));
        await _completeSuccessfulRequest(initial);
      } on UnauthorizedException catch (error) {
        if (error.code != invalidAccessCode) rethrow;
        await _performRefreshUnderLease(initial);
        throw const AuthSessionUnavailable(
          AuthSessionUnavailableReason.requestNotReplayed,
        );
      }

      await _quarantineCredentialRevision(initial);
      _sessionInvalidationSignal.emit(
        reason: reason,
        credentialRevision: initial.revision,
      );
      return result;
    } finally {
      if (initial != null) {
        _endOperation(initial.revision);
      }
      lease.release();
    }
  }

  /// Commits a successful online verification under the authentication gate by
  /// resetting the backend-sync timer. The gate keeps this from running after an
  /// account exit has drained it and cleared local authentication data.
  Future<void> markCurrentCredentialsServerVerified() async {
    final lease = _authenticationAttemptGate.tryAcquire();
    if (lease == null) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.authenticationBusy,
      );
    }

    try {
      await _commitServerVerificationSafely();
    } finally {
      lease.release();
    }
  }

  Future<_RefreshResult> _refreshFor(AuthCredentialSnapshot expected) {
    final existing = _refreshFlights[expected.revision];
    if (existing != null) return existing;

    final flight = _performRefresh(expected);
    _refreshFlights[expected.revision] = flight;
    // A failed rotation must not linger for later requests on this revision: a
    // failing refresh never advances the revision, so the cached failure would
    // be replayed to every overlapping request. Evict it the moment it errors so
    // the next request starts a fresh attempt. A success stays cached until the
    // last operation ends, keeping concurrent requests on one rotation.
    unawaited(
      flight.then(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_refreshFlights[expected.revision], flight)) {
            _refreshFlights.remove(expected.revision);
          }
        },
      ),
    );
    return flight;
  }

  void _beginOperation(int revision) {
    _activeOperationsByRevision.update(
      revision,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void _endOperation(int revision) {
    final count = _activeOperationsByRevision[revision];
    if (count == null || count <= 1) {
      _activeOperationsByRevision.remove(revision);
      _refreshFlights.remove(revision);
      return;
    }
    _activeOperationsByRevision[revision] = count - 1;
  }

  Future<_RefreshResult> _performRefresh(
    AuthCredentialSnapshot expected,
  ) async {
    final lease = _authenticationAttemptGate.tryAcquire();
    if (lease == null) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.authenticationBusy,
      );
    }

    try {
      return await _performRefreshUnderLease(expected);
    } finally {
      lease.release();
    }
  }

  Future<_RefreshResult> _performRefreshUnderLease(
    AuthCredentialSnapshot expected,
  ) async {
    await _requireCurrent(expected);

    late final AuthResponseModel response;
    try {
      response = await _authRemoteDataSource.refreshToken(
        expected.pair.refreshToken,
      );
    } on NetworkException {
      throw const AuthSessionUnavailable(AuthSessionUnavailableReason.network);
    } on UnauthorizedException catch (error) {
      if (error.code == invalidRefreshCode) {
        await _rejectInvalidRefresh(expected);
      }
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.serviceUnavailable,
      );
    } on HttpStatusException {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.serviceUnavailable,
      );
    } on FormatException {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.unexpectedRefreshResponse,
      );
    } on TypeError {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.unexpectedRefreshResponse,
      );
    }

    late final AuthTokenPair replacement;
    try {
      replacement = AuthTokenPair(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      );
    } on ArgumentError {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.unexpectedRefreshResponse,
      );
    }

    final saved = await _compareAndSet(
      expectedRevision: expected.revision,
      replacement: replacement,
    );
    if (saved == null) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialsChanged,
      );
    }

    // Credential rotation and its cached user/verification metadata are one
    // auth-state commit for account-exit ordering. The gate is released only
    // after all local writes have finished or failed.
    await _commitRefreshedSessionSafely(response);

    return _RefreshResult(response: response, snapshot: saved);
  }

  Future<Never> _rejectInvalidRefresh(AuthCredentialSnapshot expected) async {
    await _quarantineCredentialRevision(expected);

    _sessionInvalidationSignal.emitRefreshRejected(
      credentialRevision: expected.revision,
    );
    throw AuthSessionInvalid(
      AuthSessionInvalidReason.refreshRejected,
      credentialRevision: expected.revision,
    );
  }

  Future<void> _quarantineCredentialRevision(
    AuthCredentialSnapshot expected,
  ) async {
    final current = await _readSnapshot();
    if (!_sameCredentials(current, expected)) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialsChanged,
      );
    }

    try {
      final didClear = await _rejectedCredentialQuarantine
          .clearCredentialsIfRevision(expected.revision);
      if (!didClear) {
        throw const AuthSessionUnavailable(
          AuthSessionUnavailableReason.credentialsChanged,
        );
      }
    } on AuthSessionFailure {
      rethrow;
    } catch (_) {
      // A confirmed backend rejection must never become offline admission. If
      // secure deletion is temporarily unavailable, persist a restart-safe
      // cleanup marker before notifying session state.
      try {
        await _rejectedCredentialQuarantine.markAuthCleanupPending();
      } catch (_) {
        // Session state still receives a typed invalidation and fails closed in
        // this process. A simultaneous failure of both device stores cannot be
        // repaired here, but must never be reclassified as a network outage.
      }
    }
  }

  Future<AuthCredentialSnapshot> _readRequiredSnapshot() async {
    final snapshot = await _readSnapshot();
    if (snapshot == null) {
      throw const AuthSessionInvalid(
        AuthSessionInvalidReason.missingCredentials,
      );
    }
    return snapshot;
  }

  Future<AuthCredentialSnapshot?> _readSnapshot() async {
    try {
      return await _credentialVault.readCredentialSnapshot();
    } on AuthSessionFailure {
      rethrow;
    } catch (_) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialStoreUnavailable,
      );
    }
  }

  Future<AuthCredentialSnapshot?> _compareAndSet({
    required int expectedRevision,
    required AuthTokenPair replacement,
  }) async {
    try {
      return await _credentialVault.compareAndSetCredentials(
        expectedRevision: expectedRevision,
        replacement: replacement,
      );
    } catch (_) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialStoreUnavailable,
      );
    }
  }

  Future<void> _commitRefreshedSessionSafely(AuthResponseModel response) async {
    try {
      await _commitRefreshedSession(response);
    } catch (_) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialStoreUnavailable,
      );
    }
  }

  Future<void> _commitServerVerificationSafely() async {
    try {
      await _commitServerVerification();
    } catch (_) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialStoreUnavailable,
      );
    }
  }

  Future<void> _completeSuccessfulRequest(
    AuthCredentialSnapshot expected,
  ) async {
    final current = await _readSnapshot();
    if (_sameCredentials(current, expected)) return;

    // A concurrent refresh may have rotated the pair while this request was in
    // flight. The request still succeeded against the backend, so accept a
    // same-session rotation and fail only when the vault was cleared or now
    // holds a different account or session.
    if (current != null && _sameSession(current, expected)) return;

    throw const AuthSessionUnavailable(
      AuthSessionUnavailableReason.credentialsChanged,
    );
  }

  Future<void> _requireCurrent(AuthCredentialSnapshot expected) async {
    final current = await _readSnapshot();
    if (!_sameCredentials(current, expected)) {
      throw const AuthSessionUnavailable(
        AuthSessionUnavailableReason.credentialsChanged,
      );
    }
  }

  static bool _sameCredentials(
    AuthCredentialSnapshot? left,
    AuthCredentialSnapshot right,
  ) {
    return left != null &&
        left.revision == right.revision &&
        left.pair == right.pair;
  }

  /// True when both access tokens name the same account and session, i.e. one
  /// is a rotation of the other. A token that cannot be decoded, or is missing
  /// either claim, is treated as a mismatch so the caller fails closed.
  static bool _sameSession(
    AuthCredentialSnapshot left,
    AuthCredentialSnapshot right,
  ) {
    final leftClaims = _sessionClaims(left.pair.accessToken);
    if (leftClaims == null) return false;
    final rightClaims = _sessionClaims(right.pair.accessToken);
    if (rightClaims == null) return false;
    return leftClaims.sid == rightClaims.sid &&
        leftClaims.sub == rightClaims.sub;
  }

  static ({String sid, String sub})? _sessionClaims(String accessToken) {
    final Map<String, dynamic> claims;
    try {
      claims = JwtDecoder.decode(accessToken);
    } catch (_) {
      return null;
    }
    final sid = claims['sid'];
    final sub = claims['sub'];
    if (sid is! String || sid.isEmpty || sub is! String || sub.isEmpty) {
      return null;
    }
    return (sid: sid, sub: sub);
  }

  static Map<String, String> _headersFor(AuthCredentialSnapshot snapshot) {
    return Map<String, String>.unmodifiable(<String, String>{
      'Authorization': 'Bearer ${snapshot.pair.accessToken}',
    });
  }
}

class _RefreshResult {
  const _RefreshResult({required this.response, required this.snapshot});

  final AuthResponseModel response;
  final AuthCredentialSnapshot snapshot;
}
