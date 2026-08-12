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

  /// Authenticate with Google and exchange its ID token for the app's normal
  /// backend session. Null means the user canceled account selection.
  Future<UserEntity?> loginWithGoogle();

  /// Register new user
  Future<UserEntity> register(RegistrationRequestEntity request);

  /// Best-effort remote logout. Local auth data is cleared by the session
  /// coordinator only after user-scoped work has stopped.
  Future<void> logout();

  /// Best-effort native Google sign-out. Clears the cached Google account so
  /// the next Google sign-in shows the chooser instead of silently reusing the
  /// signed-out account. A no-op when the build has no Google identity service;
  /// never throws. The session coordinator calls this on every account exit —
  /// voluntary logout and forced loss alike.
  Future<void> signOutFromGoogle();

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

  /// Read the server's current safe user, including verification state.
  /// Remote-only: the session coordinator commits visible and cached state.
  Future<UserEntity> refreshCurrentUser();

  /// Ask the backend to re-send the verification email for the signed-in
  /// user. The server throttles this and answers generically.
  Future<void> resendVerificationEmail();

  /// Start a password reset for [email]. Unauthenticated; the backend answers
  /// generically, so success does not reveal whether the account exists.
  Future<void> requestPasswordReset(String email);

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
