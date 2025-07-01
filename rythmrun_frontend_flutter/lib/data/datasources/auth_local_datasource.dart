import '../../domain/entities/user_entity.dart';
import '../models/auth_response_model.dart';
import '../../core/services/auth_persistence_service.dart';

/// Local data source for authentication data
/// Handles all local storage operations
class AuthLocalDataSource {
  /// Save authentication data to secure storage
  Future<void> saveAuthData(AuthResponseModel authResponse) async {
    await AuthPersistenceService.saveAuthData(authResponse);
  }

  /// Get user data from local storage
  Future<UserEntity?> getUserData() async {
    return await AuthPersistenceService.getUserData();
  }

  /// Get access token from local storage
  Future<String?> getAccessToken() async {
    return await AuthPersistenceService.getAccessToken();
  }

  /// Get refresh token from local storage
  Future<String?> getRefreshToken() async {
    return await AuthPersistenceService.getRefreshToken();
  }

  /// Get authentication headers for API calls
  Future<Map<String, String>?> getAuthHeaders() async {
    return await AuthPersistenceService.getAuthHeaders();
  }

  /// Check if user has a valid session
  Future<bool> hasValidSession() async {
    return await AuthPersistenceService.hasValidSession();
  }

  /// Check if session has expired
  Future<bool> isSessionExpired() async {
    return await AuthPersistenceService.isSessionExpired();
  }

  /// Check if token refresh is needed
  Future<bool> needsTokenRefresh() async {
    return await AuthPersistenceService.needsTokenRefresh();
  }

  /// Clear all authentication data
  Future<void> clearAuthData() async {
    await AuthPersistenceService.clearAuthData();
  }
}
