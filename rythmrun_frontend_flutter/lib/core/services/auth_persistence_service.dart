import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../data/models/auth_response_model.dart';
import '../../domain/entities/user_entity.dart';

class AuthPersistenceService {
  // Storage keys
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userDataKey = 'user_data';
  static const String _lastBackendSyncKey = 'last_backend_sync';

  /// Write data to SharedPreferences
  static Future<void> _write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// Read data from SharedPreferences
  static Future<String?> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  /// Delete data from SharedPreferences
  static Future<void> _delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Save authentication data after successful login
  static Future<void> saveAuthData(AuthResponseModel authResponse) async {
    final now = DateTime.now().toIso8601String();

    if (kDebugMode) {
      print(
        '🔐 AuthPersistenceService: Saving auth data for user: ${authResponse.user.email}',
      );
    }

    await Future.wait([
      _write(_accessTokenKey, authResponse.accessToken),
      _write(_refreshTokenKey, authResponse.refreshToken),
      _write(_userDataKey, json.encode(authResponse.user.toJson())),
      _write(_lastBackendSyncKey, now),
    ]);

    if (kDebugMode) {
      print('✅ AuthPersistenceService: Auth data saved successfully');
    }
  }

  /// Get stored access token
  static Future<String?> getAccessToken() async {
    return await _read(_accessTokenKey);
  }

  /// Get stored refresh token
  static Future<String?> getRefreshToken() async {
    return await _read(_refreshTokenKey);
  }

  /// Get stored user data
  static Future<UserEntity?> getUserData() async {
    final userDataJson = await _read(_userDataKey);
    if (userDataJson == null) return null;

    try {
      final userData = json.decode(userDataJson) as Map<String, dynamic>;
      return UserEntity(
        id: userData['id'] as String,
        firstName: userData['firstName'] as String,
        lastName: userData['lastName'] as String,
        email: userData['email'] as String,
        profilePicturePath: userData['profilePicturePath'] as String?,
        profilePictureType: userData['profilePictureType'] as String?,
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

    if (kDebugMode) {
      print('🔍 AuthPersistenceService: Checking valid session');
      print(
        '   Access token exists: ${accessToken != null && accessToken.isNotEmpty}',
      );
    }

    if (accessToken == null || accessToken.isEmpty) {
      if (kDebugMode) {
        print('❌ AuthPersistenceService: No access token found');
      }
      return false;
    }

    try {
      // Check if token is not expired
      final isValid = !JwtDecoder.isExpired(accessToken);
      if (kDebugMode) {
        print('🔍 AuthPersistenceService: Token valid: $isValid');
      }
      return isValid;
    } catch (e) {
      // If token is malformed, consider session invalid
      if (kDebugMode) {
        print('❌ AuthPersistenceService: Token malformed: $e');
      }
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
      _write(_accessTokenKey, newAccessToken),
      _write(_refreshTokenKey, newRefreshToken),
      _write(_lastBackendSyncKey, DateTime.now().toIso8601String()),
    ]);
  }

  /// Get the last backend sync timestamp
  static Future<DateTime?> getLastBackendSync() async {
    final timestampStr = await _read(_lastBackendSyncKey);
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
    await _write(_lastBackendSyncKey, DateTime.now().toIso8601String());
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
      _delete(_accessTokenKey),
      _delete(_refreshTokenKey),
      _delete(_userDataKey),
      _delete(_lastBackendSyncKey),
    ]);
  }

  /// Update user data in local storage
  static Future<void> updateUserData(UserEntity user) async {
    final userJson = {
      'id': user.id,
      'firstName': user.firstName,
      'lastName': user.lastName,
      'email': user.email,
      'profilePicturePath': user.profilePicturePath,
      'profilePictureType': user.profilePictureType,
    };

    await _write(_userDataKey, json.encode(userJson));

    if (kDebugMode) {
      print('✅ AuthPersistenceService: User data updated in local storage');
      print('   Profile picture path: ${user.profilePicturePath}');
    }
  }

  /// Clear only user data (keep tokens for logout API call)
  static Future<void> clearUserData() async {
    await _delete(_userDataKey);
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
      'accessToken': await _read(_accessTokenKey),
      'refreshToken': await _read(_refreshTokenKey),
      'userData': await _read(_userDataKey),
      'lastBackendSync': await _read(_lastBackendSyncKey),
    };
  }

  /// Debug method to print all stored data (only for development)
  static Future<void> printStoredData() async {
    if (!kDebugMode) return;

    print('🔍 AuthPersistenceService: Checking stored data...');
    final data = await getAllStoredData();

    print(
      '   Access Token: ${data['accessToken'] != null ? 'EXISTS' : 'NULL'}',
    );
    print(
      '   Refresh Token: ${data['refreshToken'] != null ? 'EXISTS' : 'NULL'}',
    );
    print('   User Data: ${data['userData'] != null ? 'EXISTS' : 'NULL'}');
    print('   Last Backend Sync: ${data['lastBackendSync'] ?? 'NULL'}');

    if (data['accessToken'] != null) {
      try {
        final isExpired = JwtDecoder.isExpired(data['accessToken']!);
        print('   Access Token Expired: $isExpired');
      } catch (e) {
        print('   Access Token Error: $e');
      }
    }
  }
}
