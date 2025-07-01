import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/auth_response_model.dart';
import '../models/registration_request_model.dart';

class AuthRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  AuthRemoteDataSource({
    required this.client,
    this.baseUrl =
        'http://192.168.1.51:8080/api', // Android emulator can access host v
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
        return AuthResponseModel.fromJson(jsonResponse);
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
        return AuthResponseModel.fromJson(jsonResponse);
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

  Future<void> logoutUser(Map<String, String>? authHeaders) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...?authHeaders,
      };

      final response = await client.post(
        Uri.parse('$baseUrl/users/logout'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Logout failed');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<UserModel?> getCurrentUser() async {
    // TODO: Implement API call when profile endpoint is available in backend
    return null;
  }

  /// Refresh access token using the provided refresh token
  Future<AuthResponseModel> refreshToken(String refreshToken) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/users/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        return AuthResponseModel.fromJson(jsonResponse);
      } else {
        throw Exception('Token refresh failed');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
