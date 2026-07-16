import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_token_store.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
import 'package:rythmrun_frontend_flutter/core/services/google_identity_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/session_invalidation_signal.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/auth_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/models/user_model.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/auth_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';

void main() {
  test(
    'account exit drains refresh persistence and rejects another auth attempt',
    () async {
      final gate = AuthenticationAttemptGate();
      final httpClient = _testHttpClient();
      addTearDown(httpClient.close);
      final remote = _DelayedAuthRemoteDataSource(httpClient);
      final metadataWriteStarted = Completer<void>();
      final releaseMetadataWrite = Completer<void>();
      final local = _MemoryAuthLocalDataSource(
        userWriteStarted: metadataWriteStarted,
        releaseUserWrite: releaseMetadataWrite,
      );
      final invalidation = SessionInvalidationSignal();
      addTearDown(invalidation.dispose);
      final coordinator = AuthenticatedRequestCoordinator(
        credentialVault: local,
        rejectedCredentialQuarantine: local,
        authRemoteDataSource: remote,
        authenticationAttemptGate: gate,
        sessionInvalidationSignal: invalidation,
        commitRefreshedSession: (response) async {
          await local.updateUserData(response.toUserEntity());
          await local.updateLastBackendSync();
        },
        commitServerVerification: local.updateLastBackendSync,
      );
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticatedRequests: coordinator,
        authenticationAttemptGate: gate,
      );

      final pendingRefresh = repository.refreshToken();
      await Future<void>.delayed(Duration.zero);
      expect(gate.isActive, isTrue);

      await expectLater(
        repository.login(
          LoginRequestEntity(email: 'b@example.com', password: 'password'),
        ),
        throwsStateError,
      );
      expect(remote.loginCalls, 0);

      var didDrain = false;
      final drain = gate.suspendAndDrain().then((_) => didDrain = true);
      await Future<void>.delayed(Duration.zero);
      expect(didDrain, isFalse);

      remote.refreshCompleter.complete(_response);
      await metadataWriteStarted.future;
      expect(didDrain, isFalse);
      releaseMetadataWrite.complete();
      await pendingRefresh;
      await drain;
      expect(local.snapshot?.pair.accessToken, _response.accessToken);
      expect(local.user, _response.toUserEntity());

      await local.clearAuthData();
      expect(local.snapshot, isNull);
      expect(local.user, isNull);
      expect(local.hasLastBackendSync, isFalse);
      expect(gate.tryAcquire(), isNull);
    },
  );

  test(
    'account exit drains a successful server-verification timestamp',
    () async {
      final gate = AuthenticationAttemptGate();
      final httpClient = _testHttpClient();
      addTearDown(httpClient.close);
      final remote = _DelayedAuthRemoteDataSource(httpClient);
      final syncWriteStarted = Completer<void>();
      final releaseSyncWrite = Completer<void>();
      final local = _MemoryAuthLocalDataSource(
        syncWriteStarted: syncWriteStarted,
        releaseSyncWrite: releaseSyncWrite,
      );
      final invalidation = SessionInvalidationSignal();
      addTearDown(invalidation.dispose);
      final coordinator = _coordinator(
        gate: gate,
        remote: remote,
        local: local,
        invalidation: invalidation,
      );
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticatedRequests: coordinator,
        authenticationAttemptGate: gate,
      );

      final validation = repository.validateSession();
      await syncWriteStarted.future;

      var didDrain = false;
      final drain = gate.suspendAndDrain().then((_) => didDrain = true);
      await Future<void>.delayed(Duration.zero);
      expect(didDrain, isFalse);

      releaseSyncWrite.complete();
      expect(await validation, SessionValidationStatus.valid);
      await drain;
      await local.clearAuthData();

      expect(local.snapshot, isNull);
      expect(local.hasLastBackendSync, isFalse);
    },
  );

  test(
    'password change clears the local revision and signals teardown',
    () async {
      final gate = AuthenticationAttemptGate();
      final httpClient = _testHttpClient();
      addTearDown(httpClient.close);
      final remote = _DelayedAuthRemoteDataSource(httpClient);
      final local = _MemoryAuthLocalDataSource();
      final invalidation = SessionInvalidationSignal();
      addTearDown(invalidation.dispose);
      final coordinator = _coordinator(
        gate: gate,
        remote: remote,
        local: local,
        invalidation: invalidation,
      );
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticatedRequests: coordinator,
        authenticationAttemptGate: gate,
      );
      final eventFuture = invalidation.events.first;

      final response = await repository.changePassword(
        'old-password',
        'new-password',
      );

      expect(response.success, isTrue);
      expect(local.snapshot, isNull);
      final event = await eventFuture;
      expect(event.reason, SessionInvalidationReason.passwordChanged);
    },
  );

  test(
    'offline mode denies password change before revoking the session',
    () async {
      final gate = AuthenticationAttemptGate();
      final httpClient = _testHttpClient();
      addTearDown(httpClient.close);
      final remote = _DelayedAuthRemoteDataSource(httpClient);
      final local = _MemoryAuthLocalDataSource();
      final invalidation = SessionInvalidationSignal();
      addTearDown(invalidation.dispose);
      final coordinator = _coordinator(
        gate: gate,
        remote: remote,
        local: local,
        invalidation: invalidation,
      );
      final guard = OnlineOperationGuard();
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticatedRequests: coordinator,
        authenticationAttemptGate: gate,
        onlineOperationGuard: guard,
      );

      await expectLater(
        repository.changePassword('old-password', 'new-password'),
        throwsA(
          isA<AuthSessionUnavailable>().having(
            (error) => error.reason,
            'reason',
            AuthSessionUnavailableReason.offlineMode,
          ),
        ),
      );
      // The offline mutation was rejected before the session was revoked and
      // without consuming the authentication attempt gate.
      expect(local.snapshot, isNotNull);
      final lease = gate.tryAcquire();
      expect(lease, isNotNull);
      lease!.release();

      // When online, the same call proceeds and revokes the session.
      guard.setOnline(true);
      final response = await repository.changePassword(
        'old-password',
        'new-password',
      );
      expect(response.success, isTrue);
      expect(local.snapshot, isNull);
    },
  );

  test(
    'offline mode denies profile update before it reaches the network',
    () async {
      final gate = AuthenticationAttemptGate();
      final httpClient = _testHttpClient();
      addTearDown(httpClient.close);
      final remote = _DelayedAuthRemoteDataSource(httpClient);
      final local = _MemoryAuthLocalDataSource();
      final invalidation = SessionInvalidationSignal();
      addTearDown(invalidation.dispose);
      final guard = OnlineOperationGuard();
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticatedRequests: _coordinator(
          gate: gate,
          remote: remote,
          local: local,
          invalidation: invalidation,
        ),
        authenticationAttemptGate: gate,
        onlineOperationGuard: guard,
      );

      await expectLater(
        repository.updateProfile(firstName: 'Renamed', lastName: 'Runner'),
        throwsA(
          isA<AuthSessionUnavailable>().having(
            (error) => error.reason,
            'reason',
            AuthSessionUnavailableReason.offlineMode,
          ),
        ),
      );
      expect(remote.updateProfileCalls, 0);

      // Online, the same call returns the server's updated safe user.
      guard.setOnline(true);
      final updated = await repository.updateProfile(
        firstName: 'Renamed',
        lastName: 'Runner',
      );
      expect(remote.updateProfileCalls, 1);
      expect(updated.firstName, 'Renamed');
      expect(updated.lastName, 'Runner');
      expect(updated.id, '7');
    },
  );

  test(
    'Google chooser and exchange hold the auth gate against account cleanup',
    () async {
      final gate = AuthenticationAttemptGate();
      final httpClient = _testHttpClient();
      addTearDown(httpClient.close);
      final remote = _DelayedAuthRemoteDataSource(httpClient);
      final local = _MemoryAuthLocalDataSource();
      final invalidation = SessionInvalidationSignal();
      addTearDown(invalidation.dispose);
      final tokenCompleter = Completer<String?>();
      final google = _FakeGoogleIdentityService(
        authenticationCompleter: tokenCompleter,
      );
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticatedRequests: _coordinator(
          gate: gate,
          remote: remote,
          local: local,
          invalidation: invalidation,
        ),
        authenticationAttemptGate: gate,
        googleIdentityService: google,
      );

      final pendingLogin = repository.loginWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(gate.isActive, isTrue);
      expect(google.authenticateCalls, 1);

      var didDrain = false;
      final drain = gate.suspendAndDrain().then((_) => didDrain = true);
      await Future<void>.delayed(Duration.zero);
      expect(didDrain, isFalse);

      await expectLater(
        repository.login(
          LoginRequestEntity(email: 'other@example.com', password: 'password'),
        ),
        throwsStateError,
      );
      expect(remote.loginCalls, 0);

      tokenCompleter.complete('short-lived-google-id-token');
      expect(await pendingLogin, _response.toUserEntity());
      await drain;

      expect(remote.googleLoginCalls, 1);
      expect(remote.lastGoogleIdToken, 'short-lived-google-id-token');
      expect(local.user, _response.toUserEntity());
      expect(local.snapshot?.pair.accessToken, _response.accessToken);

      // Session teardown runs only after the full leased operation drains, so
      // its final clear cannot be repopulated by a late chooser result.
      await local.clearAuthData();
      expect(local.snapshot, isNull);
      expect(local.user, isNull);
    },
  );

  test('Google cancellation skips backend exchange and local writes', () async {
    final gate = AuthenticationAttemptGate();
    final httpClient = _testHttpClient();
    addTearDown(httpClient.close);
    final remote = _DelayedAuthRemoteDataSource(httpClient);
    final local = _MemoryAuthLocalDataSource();
    final invalidation = SessionInvalidationSignal();
    addTearDown(invalidation.dispose);
    final google = _FakeGoogleIdentityService(idToken: null);
    final repository = AuthRepositoryImpl(
      remote,
      local,
      authenticatedRequests: _coordinator(
        gate: gate,
        remote: remote,
        local: local,
        invalidation: invalidation,
      ),
      authenticationAttemptGate: gate,
      googleIdentityService: google,
    );
    final originalSnapshot = local.snapshot;

    final user = await repository.loginWithGoogle();

    expect(user, isNull);
    expect(remote.googleLoginCalls, 0);
    expect(local.snapshot, originalSnapshot);
    expect(google.signOutCalls, 0);
    expect(gate.isActive, isFalse);
  });

  test('failed Google backend exchange signs out the native account', () async {
    final gate = AuthenticationAttemptGate();
    final httpClient = _testHttpClient();
    addTearDown(httpClient.close);
    final remote = _DelayedAuthRemoteDataSource(httpClient)
      ..googleFailure = StateError('exchange failed');
    final local = _MemoryAuthLocalDataSource();
    final invalidation = SessionInvalidationSignal();
    addTearDown(invalidation.dispose);
    final google = _FakeGoogleIdentityService(idToken: 'google-id-token');
    final repository = AuthRepositoryImpl(
      remote,
      local,
      authenticatedRequests: _coordinator(
        gate: gate,
        remote: remote,
        local: local,
        invalidation: invalidation,
      ),
      authenticationAttemptGate: gate,
      googleIdentityService: google,
    );

    await expectLater(repository.loginWithGoogle(), throwsStateError);

    expect(google.signOutCalls, 1);
    expect(gate.isActive, isFalse);
  });

  test('logout does not wait for native Google sign-out', () async {
    final gate = AuthenticationAttemptGate();
    final httpClient = _testHttpClient();
    addTearDown(httpClient.close);
    final remote = _DelayedAuthRemoteDataSource(httpClient);
    final local = _MemoryAuthLocalDataSource();
    final invalidation = SessionInvalidationSignal();
    addTearDown(invalidation.dispose);
    final signOutCompleter = Completer<void>();
    addTearDown(() {
      if (!signOutCompleter.isCompleted) signOutCompleter.complete();
    });
    final google = _FakeGoogleIdentityService(
      signOutCompleter: signOutCompleter,
    );
    final repository = AuthRepositoryImpl(
      remote,
      local,
      authenticatedRequests: _coordinator(
        gate: gate,
        remote: remote,
        local: local,
        invalidation: invalidation,
      ),
      authenticationAttemptGate: gate,
      googleIdentityService: google,
    );

    await repository.logout();

    expect(google.signOutCalls, 1);
    expect(signOutCompleter.isCompleted, isFalse);
    expect(remote.logoutCalls, 1);
  });
}

AppHttpClient _testHttpClient() {
  return AppHttpClient(
    client: MockClient((_) async => http.Response('{}', 500)),
  );
}

AuthenticatedRequestCoordinator _coordinator({
  required AuthenticationAttemptGate gate,
  required _DelayedAuthRemoteDataSource remote,
  required _MemoryAuthLocalDataSource local,
  required SessionInvalidationSignal invalidation,
}) {
  return AuthenticatedRequestCoordinator(
    credentialVault: local,
    rejectedCredentialQuarantine: local,
    authRemoteDataSource: remote,
    authenticationAttemptGate: gate,
    sessionInvalidationSignal: invalidation,
    commitRefreshedSession: (response) async {
      await local.updateUserData(response.toUserEntity());
      await local.updateLastBackendSync();
    },
    commitServerVerification: local.updateLastBackendSync,
  );
}

const _response = AuthResponseModel(
  user: UserModel(
    id: '7',
    firstName: 'A',
    lastName: 'Runner',
    email: 'a@example.com',
  ),
  accessToken: 'access-a',
  refreshToken: 'refresh-a',
);

class _DelayedAuthRemoteDataSource extends AuthRemoteDataSource {
  _DelayedAuthRemoteDataSource(AppHttpClient httpClient)
    : super(httpClient: httpClient);

  final Completer<AuthResponseModel> refreshCompleter =
      Completer<AuthResponseModel>();
  int loginCalls = 0;
  int googleLoginCalls = 0;
  int logoutCalls = 0;
  int updateProfileCalls = 0;
  String? lastGoogleIdToken;
  Object? googleFailure;

  @override
  Future<bool> verifySession(Map<String, String> authHeaders) async => true;

  @override
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
    Map<String, String> authHeaders,
  ) async {
    return const ChangePasswordResponseModel(
      message: 'Password changed successfully',
      success: true,
    );
  }

  @override
  Future<AuthResponseModel> refreshToken(String refreshToken) {
    return refreshCompleter.future;
  }

  @override
  Future<AuthResponseModel> loginUser(String email, String password) async {
    loginCalls += 1;
    return _response;
  }

  @override
  Future<AuthResponseModel> loginWithGoogle(String idToken) async {
    googleLoginCalls += 1;
    lastGoogleIdToken = idToken;
    final failure = googleFailure;
    if (failure != null) throw failure;
    return _response;
  }

  @override
  Future<void> logoutUser(Map<String, String>? authHeaders) async {
    logoutCalls += 1;
  }

  @override
  Future<UserModel> updateProfile(
    String firstName,
    String lastName,
    Map<String, String> authHeaders,
  ) async {
    updateProfileCalls += 1;
    return UserModel(
      id: '7',
      firstName: firstName,
      lastName: lastName,
      email: 'a@example.com',
    );
  }
}

class _MemoryAuthLocalDataSource extends AuthLocalDataSource {
  _MemoryAuthLocalDataSource({
    this.userWriteStarted,
    this.releaseUserWrite,
    this.syncWriteStarted,
    this.releaseSyncWrite,
  });

  final Completer<void>? userWriteStarted;
  final Completer<void>? releaseUserWrite;
  final Completer<void>? syncWriteStarted;
  final Completer<void>? releaseSyncWrite;
  AuthCredentialSnapshot? snapshot = AuthCredentialSnapshot(
    pair: AuthTokenPair(
      accessToken: 'access-before',
      refreshToken: 'refresh-before',
    ),
    revision: 1,
    requiresServerVerification: false,
  );
  UserEntity? user;
  bool hasLastBackendSync = false;
  bool cleanupPending = false;

  @override
  Future<void> saveAuthData(AuthResponseModel authResponse) async {
    snapshot = AuthCredentialSnapshot(
      pair: AuthTokenPair(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      ),
      revision: (snapshot?.revision ?? 0) + 1,
      requiresServerVerification: false,
    );
    user = authResponse.toUserEntity();
    hasLastBackendSync = true;
  }

  @override
  Future<AuthCredentialSnapshot?> readCredentialSnapshot() async => snapshot;

  @override
  Future<AuthCredentialSnapshot?> compareAndSetCredentials({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  }) async {
    if (snapshot?.revision != expectedRevision) return null;
    snapshot = AuthCredentialSnapshot(
      pair: replacement,
      revision: expectedRevision + 1,
      requiresServerVerification: requiresServerVerification,
    );
    return snapshot;
  }

  @override
  Future<AuthCredentialSnapshot?> markCredentialsServerVerified({
    required int expectedRevision,
  }) async => snapshot;

  @override
  Future<void> updateUserData(UserEntity updatedUser) async {
    userWriteStarted?.complete();
    await releaseUserWrite?.future;
    user = updatedUser;
  }

  @override
  Future<void> updateLastBackendSync() async {
    syncWriteStarted?.complete();
    await releaseSyncWrite?.future;
    hasLastBackendSync = true;
  }

  @override
  Future<bool> hasValidSession() async => snapshot != null;

  @override
  Future<bool> needsBackendSync() async => true;

  @override
  Future<bool> clearCredentialsIfRevision(int expectedRevision) async {
    if (snapshot == null) return true;
    if (snapshot?.revision != expectedRevision) return false;
    snapshot = null;
    return true;
  }

  @override
  Future<void> markAuthCleanupPending() async {
    cleanupPending = true;
  }

  @override
  Future<void> clearAuthData() async {
    snapshot = null;
    user = null;
    hasLastBackendSync = false;
    cleanupPending = false;
  }
}

class _FakeGoogleIdentityService implements GoogleIdentityService {
  _FakeGoogleIdentityService({
    this.idToken = 'google-id-token',
    this.authenticationCompleter,
    this.signOutCompleter,
  });

  final String? idToken;
  final Completer<String?>? authenticationCompleter;
  final Completer<void>? signOutCompleter;
  int authenticateCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String?> authenticate() async {
    authenticateCalls += 1;
    return authenticationCompleter?.future ?? idToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    await signOutCompleter?.future;
  }
}
