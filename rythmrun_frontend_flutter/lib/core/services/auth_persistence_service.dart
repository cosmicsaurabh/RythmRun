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
  static const String _loginTimestampKey = 'login_timestamp';

  /// Save authentication data after successful login
  static Future<void> saveAuthData(AuthResponseModel authResponse) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: authResponse.accessToken),
      _storage.write(key: _refreshTokenKey, value: authResponse.refreshToken),
      _storage.write(
        key: _userDataKey,
        value: json.encode(authResponse.user.toJson()),
      ),
      _storage.write(
        key: _loginTimestampKey,
        value: DateTime.now().toIso8601String(),
      ),
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
    ]);
  }

  /// Check how long user has been logged in
  static Future<Duration?> getSessionDuration() async {
    final timestampStr = await _storage.read(key: _loginTimestampKey);
    if (timestampStr == null) return null;

    try {
      final loginTime = DateTime.parse(timestampStr);
      return DateTime.now().difference(loginTime);
    } catch (e) {
      return null;
    }
  }

  /// Check if session has exceeded maximum duration (e.g., 30 days)
  static Future<bool> isSessionExpired({
    Duration maxDuration = const Duration(days: 30),
  }) async {
    final sessionDuration = await getSessionDuration();
    if (sessionDuration == null) return true;

    return sessionDuration > maxDuration;
  }

  /// Clear all stored authentication data
  static Future<void> clearAuthData() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userDataKey),
      _storage.delete(key: _loginTimestampKey),
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
      'loginTimestamp': await _storage.read(key: _loginTimestampKey),
    };
  }
}
