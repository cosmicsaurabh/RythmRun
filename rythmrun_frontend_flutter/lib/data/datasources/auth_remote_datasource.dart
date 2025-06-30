import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/auth_response_model.dart';
import '../models/registration_request_model.dart';
import '../../core/services/auth_persistence_service.dart';

class AuthRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  AuthRemoteDataSource({
    required this.client,
    this.baseUrl =
        'http://192.168.1.82:8080/api', // Android emulator can access host v
  });

  Future<AuthResponseModel> registerUser(
    RegistrationRequestModel request,
  ) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/users/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 201) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final authResponse = AuthResponseModel.fromJson(jsonResponse);

        // Save tokens to secure storage
        await AuthPersistenceService.saveAuthData(authResponse);

        return authResponse;
      } else if (response.statusCode == 400) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        throw Exception(jsonResponse['message'] ?? 'Registration failed');
      } else {
        throw Exception('Registration failed');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<AuthResponseModel> loginUser(String email, String password) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/users/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final authResponse = AuthResponseModel.fromJson(jsonResponse);

        // Save tokens to secure storage
        await AuthPersistenceService.saveAuthData(authResponse);

        return authResponse;
      } else if (response.statusCode == 401) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        throw Exception(jsonResponse['message'] ?? 'Invalid credentials');
      } else {
        throw Exception('Login failed');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> logoutUser() async {
    try {
      // Get auth headers for the logout request
      final headers = await AuthPersistenceService.getAuthHeaders();

      final response = await client.post(
        Uri.parse('$baseUrl/users/logout'),
        headers: headers ?? {'Content-Type': 'application/json'},
      );

      // Clear stored data regardless of server response
      // (in case server is down, we still want to log out locally)
      await AuthPersistenceService.clearAuthData();

      if (response.statusCode != 200) {
        // Don't throw here since we've already cleared local data
        print('Server logout failed, but local logout successful');
      }
    } catch (e) {
      // Even if network fails, clear local data
      await AuthPersistenceService.clearAuthData();
      throw Exception(e.toString());
    }
  }

  Future<UserModel?> getCurrentUser() async {
    // Try to get user from stored data first
    final userData = await AuthPersistenceService.getUserData();
    if (userData != null) {
      return UserModel(
        id: userData.id,
        firstName: userData.firstName,
        lastName: userData.lastName,
        email: userData.email,
        createdAt: userData.createdAt,
      );
    }

    // TODO: Implement API call when profile endpoint is available in backend
    return null;
  }

  /// Refresh access token using the stored refresh token
  Future<AuthResponseModel> refreshToken() async {
    try {
      final refreshToken = await AuthPersistenceService.getRefreshToken();
      if (refreshToken == null) {
        throw Exception('No refresh token available');
      }

      final response = await client.post(
        Uri.parse('$baseUrl/users/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final data = jsonResponse['data'] as Map<String, dynamic>;

        // Update tokens in storage
        await AuthPersistenceService.updateTokens(
          data['accessToken'] as String,
          data['refreshToken'] as String,
        );

        // Return the updated auth response with existing user data
        final userData = await AuthPersistenceService.getUserData();
        if (userData != null) {
          final userModel = UserModel(
            id: userData.id,
            firstName: userData.firstName,
            lastName: userData.lastName,
            email: userData.email,
            createdAt: userData.createdAt,
          );

          return AuthResponseModel(
            user: userModel,
            accessToken: data['accessToken'] as String,
            refreshToken: data['refreshToken'] as String,
          );
        } else {
          throw Exception('User data not found after token refresh');
        }
      } else {
        throw Exception('Token refresh failed');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
