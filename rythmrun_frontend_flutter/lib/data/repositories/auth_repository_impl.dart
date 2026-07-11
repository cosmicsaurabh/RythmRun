import 'dart:developer';

import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';

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
  final AuthenticationAttemptGate? _authenticationAttemptGate;

  AuthRepositoryImpl(
    this._remoteDataSource,
    this._localDataSource, {
    AuthenticationAttemptGate? authenticationAttemptGate,
  }) : _authenticationAttemptGate = authenticationAttemptGate;

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
      try {
        // 1. Call remote API
        final authResponse = await _remoteDataSource.loginUser(
          request.email,
          request.password,
        );

        // 2. Save to local storage
        await _localDataSource.saveAuthData(authResponse);

        // 3. Return user entity
        return authResponse.toUserEntity();
      } catch (e) {
        // Clear any partial data on error
        await _localDataSource.clearAuthData();
        rethrow;
      }
    });
  }

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) async {
    return _runAuthenticationMutation(() async {
      try {
        // 1. Convert entity to model
        final requestModel = RegistrationRequestModel.fromEntity(request);

        // 2. Call remote API
        final authResponse = await _remoteDataSource.registerUser(requestModel);

        // 3. Save to local storage
        await _localDataSource.saveAuthData(authResponse);

        // 4. Return user entity
        return authResponse.toUserEntity();
      } catch (e) {
        // Clear any partial data on error
        await _localDataSource.clearAuthData();
        rethrow;
      }
    });
  }

  @override
  Future<void> logout() async {
    try {
      // 1. Get auth headers for the logout request
      final authHeaders = await _localDataSource.getAuthHeaders();

      // 2. Try to call remote API (but don't fail if it doesn't work)
      await _remoteDataSource.logoutUser(authHeaders);
    } catch (e) {
      // Remote revocation is best effort; SessionNotifier owns local cleanup.
      log('Remote logout failed: $e');
    }
  }

  @override
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      // Get auth headers for the request
      final authHeaders = await _localDataSource.getAuthHeaders();
      if (authHeaders == null) {
        throw Exception('Not authenticated');
      }

      final response = await _remoteDataSource.changePassword(
        currentPassword,
        newPassword,
        authHeaders,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Check if user has valid offline access (local data available)
  @override
  Future<bool> hasOfflineAccess() async {
    final userData = await _localDataSource.getUserData();
    return userData != null;
  }

  @override
  Future<UserEntity> refreshToken() async {
    return _runAuthenticationMutation(() async {
      try {
        // 1. Get refresh token from local storage
        final refreshToken = await _localDataSource.getRefreshToken();
        if (refreshToken == null) {
          throw Exception('No refresh token available');
        }

        // 2. Call remote API
        final authResponse = await _remoteDataSource.refreshToken(refreshToken);

        // 3. Update local storage
        await _localDataSource.saveAuthData(authResponse);

        // 4. Return user entity
        return authResponse.toUserEntity();
      } catch (e) {
        // Don't clear data immediately on refresh failure
        // This could be a network issue - preserve offline access
        log('AuthRepository: Token refresh failed: $e');

        rethrow;
      }
    });
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    // Get user from local storage only
    return await _localDataSource.getUserData();
  }

  @override
  Future<bool> needsTokenRefresh() async {
    return await _localDataSource.needsTokenRefresh();
  }

  @override
  Future<SessionValidationStatus> validateSession() {
    return _runAuthenticationMutation(_validateSession);
  }

  Future<SessionValidationStatus> _validateSession() async {
    if (!await _localDataSource.hasValidSession()) {
      return SessionValidationStatus.invalid;
    }

    // Check if we need backend sync (7-day requirement)
    if (await _localDataSource.needsBackendSync()) {
      log('AuthRepository: Backend sync required (7-day limit reached)');

      // Try to verify with server
      try {
        final authHeaders = await _localDataSource.getAuthHeaders();
        if (authHeaders != null) {
          final isValid = await _remoteDataSource.verifySession(authHeaders);
          if (isValid) {
            // Update sync timestamp
            await _localDataSource.updateLastBackendSync();
            return SessionValidationStatus.valid;
          }
          return SessionValidationStatus.unavailable;
        } else {
          return SessionValidationStatus.invalid;
        }
      } catch (e) {
        final message = e.toString();
        if (message.contains('UnauthorizedException') ||
            message.contains('ForbiddenException') ||
            message.contains('(401)') ||
            message.contains('(403)')) {
          return SessionValidationStatus.invalid;
        }
        log(
          'AuthRepository: Server verification failed, allowing offline access: $e',
        );
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

  /// Debug method to print stored data (only for development)
  @override
  Future<void> printStoredData() async {
    await _localDataSource.printStoredData();
  }
}
