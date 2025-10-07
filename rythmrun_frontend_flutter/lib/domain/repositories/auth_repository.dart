import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';

import '../entities/user_entity.dart';
import '../entities/login_request_entity.dart';
import '../entities/registration_request_entity.dart';

/// Domain repository interface for authentication operations
/// This defines the contract that the data layer must implement
abstract class AuthRepository {
  /// Login user with email and password
  Future<UserEntity> login(LoginRequestEntity request);

  /// Register new user
  Future<UserEntity> register(RegistrationRequestEntity request);

  /// Logout current user
  Future<void> logout();

  /// Change password
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
  );

  /// Refresh access token using refresh token
  Future<UserEntity> refreshToken();

  /// Get current authenticated user
  Future<UserEntity?> getCurrentUser();

  /// Check if session needs token refresh
  Future<bool> needsTokenRefresh();

  /// Validate current session
  Future<bool> validateSession();

  /// Check if user has offline access (local data available)
  Future<bool> hasOfflineAccess();

  /// Clear all authentication data
  Future<void> clearAuthData();

  /// Check if user can stay logged in offline (has valid session and within sync window)
  Future<bool> canStayLoggedInOffline();

  /// Check if backend sync is required (7 days since last sync)
  Future<bool> needsBackendSync();

  /// Update the last backend sync timestamp
  Future<void> updateLastBackendSync();

  /// Debug method to print stored data (only for development)
  Future<void> printStoredData();
}
