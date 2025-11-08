import 'dart:developer';

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

  AuthRepositoryImpl(this._remoteDataSource, this._localDataSource);

  @override
  Future<UserEntity> login(LoginRequestEntity request) async {
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
  }

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) async {
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
  }

  @override
  Future<void> logout() async {
    try {
      // 1. Get auth headers for the logout request
      final authHeaders = await _localDataSource.getAuthHeaders();

      // 2. Try to call remote API (but don't fail if it doesn't work)
      await _remoteDataSource.logoutUser(authHeaders);
    } catch (e) {
      // Log error but continue with local cleanup

      log('Remote logout failed: $e');
    } finally {
      // 3. Always clear local data
      await _localDataSource.clearAuthData();
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

      // Only clear data if it's a genuine auth error (not network)
      if (e.toString().contains('401') || e.toString().contains('403')) {
        await _localDataSource.clearAuthData();
      }

      rethrow;
    }
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
  Future<bool> validateSession() async {
    if (!await _localDataSource.hasValidSession()) {
      return false;
    }

    // Check if token is still valid locally
    if (!await _localDataSource.hasValidSession()) {
      // Try to refresh if we have a refresh token
      if (await _localDataSource.needsTokenRefresh()) {
        try {
          await refreshToken();
          return true;
        } catch (e) {
          // Token refresh failed - but don't clear local data immediately
          // This could be a network issue, allow offline access
          log(
            'AuthRepository: Token refresh failed, allowing offline access: $e',
          );
          return false; // Return false but don't clear data
        }
      } else {
        // No refresh token available - this is a genuine auth failure
        await _localDataSource.clearAuthData();
        return false;
      }
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
            return true;
          } else {
            // Session is invalid on server
            await _localDataSource.clearAuthData();
            return false;
          }
        } else {
          // No auth headers available
          await _localDataSource.clearAuthData();
          return false;
        }
      } catch (e) {
        // Server verification failed - could be network issue
        // Don't clear local data, allow offline access
        log(
          'AuthRepository: Server verification failed, allowing offline access: $e',
        );
        return false;
      }
    }

    // Within sync window, just verify JWT locally
    return true;
  }

  @override
  Future<void> clearAuthData() async {
    await _localDataSource.clearAuthData();
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
