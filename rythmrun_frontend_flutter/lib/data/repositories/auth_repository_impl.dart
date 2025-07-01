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
      // Clear data on refresh failure
      await _localDataSource.clearAuthData();
      rethrow;
    }
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    // Get user from local storage only
    return await _localDataSource.getUserData();
  }

  @override
  Future<bool> isAuthenticated() async {
    return await _localDataSource.hasValidSession();
  }

  @override
  Future<bool> needsTokenRefresh() async {
    return await _localDataSource.needsTokenRefresh();
  }

  @override
  Future<bool> validateSession() async {
    if (!await isAuthenticated()) {
      return false;
    }

    // Check if token is still valid
    if (!await _localDataSource.hasValidSession()) {
      // Try to refresh
      if (await _localDataSource.needsTokenRefresh()) {
        try {
          await refreshToken();
          return true;
        } catch (e) {
          await _localDataSource.clearAuthData();
          return false;
        }
      } else {
        await _localDataSource.clearAuthData();
        return false;
      }
    }

    return true;
  }

  @override
  Future<void> clearAuthData() async {
    await _localDataSource.clearAuthData();
  }
}
