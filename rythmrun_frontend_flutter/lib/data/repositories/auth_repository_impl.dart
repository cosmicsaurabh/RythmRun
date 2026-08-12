import 'dart:developer';

import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
import 'package:rythmrun_frontend_flutter/core/services/session_invalidation_signal.dart';
import 'package:rythmrun_frontend_flutter/core/services/google_identity_service.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/models/auth_response_model.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/entities/login_request_entity.dart';
import '../../domain/entities/registration_request_entity.dart';
import '../datasources/auth_remote_datasource.dart';
import '../datasources/auth_local_datasource.dart';
import '../models/registration_request_model.dart';

/// Implementation of AuthRepository that coordinates between remote and local data sources
/// This follows the Repository pattern and clean architecture principles
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;
  final AuthenticatedRequestCoordinator _authenticatedRequests;
  final AuthenticationAttemptGate? _authenticationAttemptGate;
  final OnlineOperationGuard? _onlineOperationGuard;
  final GoogleIdentityService? _googleIdentityService;

  AuthRepositoryImpl(
    this._remoteDataSource,
    this._localDataSource, {
    required AuthenticatedRequestCoordinator authenticatedRequests,
    AuthenticationAttemptGate? authenticationAttemptGate,
    OnlineOperationGuard? onlineOperationGuard,
    GoogleIdentityService? googleIdentityService,
  }) : _authenticatedRequests = authenticatedRequests,
       _authenticationAttemptGate = authenticationAttemptGate,
       _onlineOperationGuard = onlineOperationGuard,
       _googleIdentityService = googleIdentityService;

  Future<T> _runAuthenticationMutation<T>(Future<T> Function() action) async {
    final lease = _authenticationAttemptGate?.tryAcquire();
    if (_authenticationAttemptGate != null && lease == null) {
      throw StateError(
        'Authentication changes are paused or another attempt is in progress.',
      );
    }
    try {
      return await action();
    } finally {
      lease?.release();
    }
  }

  @override
  Future<UserEntity> login(LoginRequestEntity request) async {
    return _runAuthenticationMutation(() async {
      final authResponse = await _remoteDataSource.loginUser(
        request.email,
        request.password,
      );
      await _commitAuthentication(authResponse);
      return authResponse.toUserEntity();
    });
  }

  @override
  Future<UserEntity?> loginWithGoogle() async {
    final googleIdentityService = _googleIdentityService;
    if (googleIdentityService == null) {
      throw const GoogleIdentityException(
        'Google sign-in is not available in this build.',
      );
    }

    return _runAuthenticationMutation(() async {
      var nativeAuthenticationCompleted = false;
      try {
        // Keep the native chooser, backend exchange, and local credential
        // commit under one authentication lease. Account teardown drains this
        // whole operation before clearing user-scoped data.
        final idToken = await googleIdentityService.authenticate();
        if (idToken == null) return null;
        nativeAuthenticationCompleted = true;

        final authResponse = await _remoteDataSource.loginWithGoogle(idToken);
        await _commitAuthentication(authResponse);
        return authResponse.toUserEntity();
      } catch (_) {
        if (nativeAuthenticationCompleted) {
          await _bestEffortGoogleSignOut(googleIdentityService);
        }
        rethrow;
      }
    });
  }

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) async {
    return _runAuthenticationMutation(() async {
      final requestModel = RegistrationRequestModel.fromEntity(request);
      final authResponse = await _remoteDataSource.registerUser(requestModel);
      await _commitAuthentication(authResponse);
      return authResponse.toUserEntity();
    });
  }

  Future<void> _commitAuthentication(AuthResponseModel authResponse) async {
    try {
      await _localDataSource.saveAuthData(authResponse);
    } catch (_) {
      // A failed local commit must not leave an orphan credential pair.
      await _localDataSource.clearAuthData();
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _authenticatedRequests.execute(
        replayPolicy: AuthenticatedReplayPolicy.idempotent,
        request: _remoteDataSource.logoutUser,
      );
    } catch (_) {
      // Remote revocation is best effort; SessionNotifier owns local cleanup.
      log('Remote logout could not be completed.');
    }
  }

  @override
  Future<void> signOutFromGoogle() async {
    final googleIdentityService = _googleIdentityService;
    if (googleIdentityService == null) return;
    await _bestEffortGoogleSignOut(googleIdentityService);
  }

  Future<void> _bestEffortGoogleSignOut(
    GoogleIdentityService googleIdentityService,
  ) async {
    try {
      await googleIdentityService.signOut();
    } catch (_) {
      log('Native Google sign-out could not be completed.');
    }
  }

  @override
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    // Deny an account mutation in offline mode with a clear message instead of
    // letting it reach the network and fail generically (IP-2.3).
    _onlineOperationGuard?.requireOnline();
    return _authenticatedRequests.executeSessionRevoking(
      reason: SessionInvalidationReason.passwordChanged,
      request:
          (authHeaders) => _remoteDataSource.changePassword(
            currentPassword,
            newPassword,
            authHeaders,
          ),
    );
  }

  /// Check if user has valid offline access (local data available)
  @override
  Future<bool> hasOfflineAccess() async {
    final userData = await _localDataSource.getUserData();
    return userData != null;
  }

  @override
  Future<UserEntity> refreshToken() async {
    // The coordinator owns the AuthenticationAttemptGate lease and commits
    // both the rotated pair and cached session metadata before releasing it.
    final authResponse = await _authenticatedRequests.refreshSession();
    return authResponse.toUserEntity();
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    // Get user from local storage only
    return await _localDataSource.getUserData();
  }

  @override
  Future<void> updateCurrentUser(UserEntity user) {
    return _localDataSource.updateUserData(user);
  }

  @override
  Future<UserEntity> refreshCurrentUser() async {
    // A read, so it stays allowed offline-guard-free and simply fails if the
    // network is down. One post-refresh replay is safe for a GET.
    final user = await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request: _remoteDataSource.fetchCurrentUser,
    );
    return user.toEntity();
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    // Unauthenticated pre-login request: no auth coordinator, no online guard.
    // Network/server errors propagate so the UI can offer a retry.
    await _remoteDataSource.requestPasswordReset(email);
  }

  @override
  Future<void> resendVerificationEmail() async {
    // Sending mail is an online-only action; the server throttles repeats, so
    // a single post-refresh replay is safe.
    _onlineOperationGuard?.requireOnline();
    await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request: _remoteDataSource.resendVerificationEmail,
    );
  }

  @override
  Future<UserEntity> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    // Profile edit is an online-only mutation (IP-2.3 guard). The PUT payload
    // is fixed, so one post-refresh replay is safe.
    _onlineOperationGuard?.requireOnline();
    final updated = await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) =>
              _remoteDataSource.updateProfile(firstName, lastName, authHeaders),
    );
    return updated.toEntity();
  }

  @override
  Future<bool> needsTokenRefresh() async {
    return await _localDataSource.needsTokenRefresh();
  }

  @override
  Future<SessionValidationStatus> validateSession() {
    return _validateSession();
  }

  Future<SessionValidationStatus> _validateSession() async {
    if (!await _localDataSource.hasValidSession()) {
      return SessionValidationStatus.invalid;
    }

    final credentialSnapshot = await _localDataSource.readCredentialSnapshot();
    if (credentialSnapshot == null) {
      return SessionValidationStatus.invalid;
    }
    final requiresServerCheck = await _localDataSource.needsBackendSync();

    if (requiresServerCheck) {
      try {
        final isValid = await _authenticatedRequests.execute(
          replayPolicy: AuthenticatedReplayPolicy.idempotent,
          request: _remoteDataSource.verifySession,
        );
        if (!isValid) {
          return SessionValidationStatus.invalid;
        }
        await _authenticatedRequests.markCurrentCredentialsServerVerified();
        return SessionValidationStatus.valid;
      } on AuthSessionInvalid {
        return SessionValidationStatus.invalid;
      } on UnauthorizedException {
        return SessionValidationStatus.invalid;
      } on AuthSessionUnavailable {
        return SessionValidationStatus.unavailable;
      } on NetworkException {
        return SessionValidationStatus.unavailable;
      } on ServerException {
        return SessionValidationStatus.unavailable;
      }
    }

    // Within sync window, just verify JWT locally
    return SessionValidationStatus.valid;
  }

  @override
  Future<void> clearAuthData() async {
    await _localDataSource.clearAuthData();
  }

  @override
  Future<void> markAuthCleanupPending() async {
    await _localDataSource.markAuthCleanupPending();
  }

  @override
  Future<bool> hasPendingAuthCleanup() async {
    return _localDataSource.hasPendingAuthCleanup();
  }

  /// Check if user can stay logged in offline (has valid session and within sync window)
  @override
  Future<bool> canStayLoggedInOffline() async {
    return await _localDataSource.canStayLoggedInOffline();
  }

  /// Check if backend sync is required (7 days since last sync)
  @override
  Future<bool> needsBackendSync() async {
    return await _localDataSource.needsBackendSync();
  }

  /// Update the last backend sync timestamp
  @override
  Future<void> updateLastBackendSync() async {
    await _localDataSource.updateLastBackendSync();
  }

  @override
  Future<bool> isHistoryRestored(String userId) async {
    return await _localDataSource.isHistoryRestored(userId);
  }

  @override
  Future<void> setHistoryRestored(String userId, bool value) async {
    await _localDataSource.setHistoryRestored(userId, value);
  }
}
