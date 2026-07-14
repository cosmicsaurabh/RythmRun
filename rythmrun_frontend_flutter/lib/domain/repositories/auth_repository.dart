import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';

import '../entities/user_entity.dart';
import '../entities/login_request_entity.dart';
import '../entities/registration_request_entity.dart';

enum SessionValidationStatus { valid, invalid, unavailable }

/// Domain repository interface for authentication operations
/// This defines the contract that the data layer must implement
abstract class AuthRepository {
  /// Login user with email and password
  Future<UserEntity> login(LoginRequestEntity request);

  /// Register new user
  Future<UserEntity> register(RegistrationRequestEntity request);

  /// Best-effort remote logout. Local auth data is cleared by the session
  /// coordinator only after user-scoped work has stopped.
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

  /// Persist non-secret cached profile metadata for the active user.
  Future<void> updateCurrentUser(UserEntity user);

  /// Update first/last name on the server and return the updated safe user.
  /// Remote-only: the session coordinator commits visible and cached state.
  Future<UserEntity> updateProfile({
    required String firstName,
    required String lastName,
  });

  /// Check if session needs token refresh
  Future<bool> needsTokenRefresh();

  /// Validate without clearing/replacing persisted credentials or user data.
  /// A successful backend verification may advance its safe sync timestamp.
  Future<SessionValidationStatus> validateSession();

  /// Check if user has offline access (local data available)
  Future<bool> hasOfflineAccess();

  /// Clear all authentication data
  Future<void> clearAuthData();

  /// Persist a fail-closed recovery marker before credential removal.
  Future<void> markAuthCleanupPending();

  /// Whether a previous account exit still needs credential cleanup.
  Future<bool> hasPendingAuthCleanup();

  /// Check if user can stay logged in offline (has valid session and within sync window)
  Future<bool> canStayLoggedInOffline();

  /// Check if backend sync is required (7 days since last sync)
  Future<bool> needsBackendSync();

  /// Update the last backend sync timestamp
  Future<void> updateLastBackendSync();
}
