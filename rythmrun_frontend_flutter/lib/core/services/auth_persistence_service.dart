import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../data/models/auth_response_model.dart';
import '../../domain/entities/user_entity.dart';

class AuthPersistenceService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Storage keys
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userDataKey = 'user_data';
  static const String _lastBackendSyncKey = 'last_backend_sync';

  /// Save authentication data after successful login
  static Future<void> saveAuthData(AuthResponseModel authResponse) async {
    final now = DateTime.now().toIso8601String();
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: authResponse.accessToken),
      _storage.write(key: _refreshTokenKey, value: authResponse.refreshToken),
      _storage.write(
        key: _userDataKey,
        value: json.encode(authResponse.user.toJson()),
      ),
      _storage.write(key: _lastBackendSyncKey, value: now),
    ]);
  }

  /// Get stored access token
  static Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  /// Get stored refresh token
  static Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  /// Get stored user data
  static Future<UserEntity?> getUserData() async {
    final userDataJson = await _storage.read(key: _userDataKey);
    if (userDataJson == null) return null;

    try {
      final userData = json.decode(userDataJson) as Map<String, dynamic>;
      return UserEntity(
        id: userData['id'] as String,
        firstName: userData['firstName'] as String,
        lastName: userData['lastName'] as String,
        email: userData['email'] as String,
        createdAt:
            userData['createdAt'] != null
                ? DateTime.parse(userData['createdAt'] as String)
                : null,
      );
    } catch (e) {
      // If user data is corrupted, clear it
      await clearUserData();
      return null;
    }
  }

  /// Check if user has a valid session
  static Future<bool> hasValidSession() async {
    final accessToken = await getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }

    try {
      // Check if token is not expired
      return !JwtDecoder.isExpired(accessToken);
    } catch (e) {
      // If token is malformed, consider session invalid
      return false;
    }
  }

  /// Check if access token is expired but refresh token might be valid
  static Future<bool> needsTokenRefresh() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();

    if (accessToken == null || refreshToken == null) {
      return false;
    }

    try {
      // Access token expired but refresh token still valid
      return JwtDecoder.isExpired(accessToken) &&
          !JwtDecoder.isExpired(refreshToken);
    } catch (e) {
      return false;
    }
  }

  /// Update tokens after refresh
  static Future<void> updateTokens(
    String newAccessToken,
    String newRefreshToken,
  ) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: newAccessToken),
      _storage.write(key: _refreshTokenKey, value: newRefreshToken),
      _storage.write(
        key: _lastBackendSyncKey,
        value: DateTime.now().toIso8601String(),
      ),
    ]);
  }

  /// Get the last backend sync timestamp
  static Future<DateTime?> getLastBackendSync() async {
    final timestampStr = await _storage.read(key: _lastBackendSyncKey);
    if (timestampStr == null) return null;

    try {
      return DateTime.parse(timestampStr);
    } catch (e) {
      return null;
    }
  }

  /// Check if backend sync is required (7 days since last sync)
  static Future<bool> needsBackendSync({
    Duration syncInterval = const Duration(days: 7),
  }) async {
    final lastSync = await getLastBackendSync();
    if (lastSync == null) return true;

    final timeSinceLastSync = DateTime.now().difference(lastSync);
    return timeSinceLastSync > syncInterval;
  }

  /// Update the last backend sync timestamp
  static Future<void> updateLastBackendSync() async {
    await _storage.write(
      key: _lastBackendSyncKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  /// Check if user can stay logged in offline (has valid session and within sync window)
  static Future<bool> canStayLoggedInOffline() async {
    // Check if we have valid tokens
    if (!await hasValidSession()) {
      return false;
    }

    // Check if we're within the sync window (7 days)
    if (await needsBackendSync()) {
      return false;
    }

    return true;
  }

  /// Clear all stored authentication data
  static Future<void> clearAuthData() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userDataKey),
      _storage.delete(key: _lastBackendSyncKey),
    ]);
  }

  /// Clear only user data (keep tokens for logout API call)
  static Future<void> clearUserData() async {
    await _storage.delete(key: _userDataKey);
  }

  /// Get authorization header for API calls
  static Future<Map<String, String>?> getAuthHeaders() async {
    final token = await getAccessToken();
    if (token == null) return null;

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Debug method to check what's stored (only for development)
  static Future<Map<String, String?>> getAllStoredData() async {
    return {
      'accessToken': await _storage.read(key: _accessTokenKey),
      'refreshToken': await _storage.read(key: _refreshTokenKey),
      'userData': await _storage.read(key: _userDataKey),
      'lastBackendSync': await _storage.read(key: _lastBackendSyncKey),
    };
  }
}
