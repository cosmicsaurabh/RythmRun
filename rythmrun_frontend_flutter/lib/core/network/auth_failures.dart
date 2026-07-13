/// Typed session failures keep transient connectivity/service problems separate
/// from credentials that the backend has explicitly rejected.
sealed class AuthSessionFailure implements Exception {
  const AuthSessionFailure();

  String get code;
  String get message;
  bool get retryable;

  @override
  String toString() => '$runtimeType($code): $message';
}

enum AuthSessionUnavailableReason {
  network,
  serviceUnavailable,
  authenticationBusy,
  credentialsChanged,
  credentialStoreUnavailable,
  requestNotReplayed,
  unexpectedRefreshResponse,
}

final class AuthSessionUnavailable extends AuthSessionFailure {
  final AuthSessionUnavailableReason reason;

  const AuthSessionUnavailable(this.reason);

  @override
  String get code => switch (reason) {
    AuthSessionUnavailableReason.network => 'AUTH_NETWORK_UNAVAILABLE',
    AuthSessionUnavailableReason.serviceUnavailable =>
      'AUTH_SERVICE_UNAVAILABLE',
    AuthSessionUnavailableReason.authenticationBusy =>
      'AUTHENTICATION_IN_PROGRESS',
    AuthSessionUnavailableReason.credentialsChanged =>
      'AUTH_CREDENTIALS_CHANGED',
    AuthSessionUnavailableReason.credentialStoreUnavailable =>
      'AUTH_CREDENTIAL_STORE_UNAVAILABLE',
    AuthSessionUnavailableReason.requestNotReplayed =>
      'AUTH_REQUEST_NOT_REPLAYED',
    AuthSessionUnavailableReason.unexpectedRefreshResponse =>
      'AUTH_REFRESH_RESPONSE_INVALID',
  };

  @override
  String get message => switch (reason) {
    AuthSessionUnavailableReason.network =>
      'The session could not be refreshed while offline.',
    AuthSessionUnavailableReason.serviceUnavailable =>
      'The authentication service is temporarily unavailable.',
    AuthSessionUnavailableReason.authenticationBusy =>
      'Another authentication change is in progress.',
    AuthSessionUnavailableReason.credentialsChanged =>
      'The active account changed while the request was in progress.',
    AuthSessionUnavailableReason.credentialStoreUnavailable =>
      'The secure session store is temporarily unavailable.',
    AuthSessionUnavailableReason.requestNotReplayed =>
      'The session was refreshed, but this request must be submitted again.',
    AuthSessionUnavailableReason.unexpectedRefreshResponse =>
      'The authentication service returned an unexpected response.',
  };

  @override
  bool get retryable => true;
}

enum AuthSessionInvalidReason { missingCredentials, refreshRejected }

final class AuthSessionInvalid extends AuthSessionFailure {
  final AuthSessionInvalidReason reason;
  final int? credentialRevision;

  const AuthSessionInvalid(this.reason, {this.credentialRevision});

  @override
  String get code => switch (reason) {
    AuthSessionInvalidReason.missingCredentials => 'AUTH_SESSION_MISSING',
    AuthSessionInvalidReason.refreshRejected => 'AUTH_REFRESH_INVALID',
  };

  @override
  String get message => switch (reason) {
    AuthSessionInvalidReason.missingCredentials =>
      'An authenticated session is required.',
    AuthSessionInvalidReason.refreshRejected =>
      'The session is no longer valid.',
  };

  @override
  bool get retryable => false;
}
