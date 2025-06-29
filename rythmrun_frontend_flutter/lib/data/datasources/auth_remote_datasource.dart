import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/registration_request_model.dart';

class AuthRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  AuthRemoteDataSource({
    required this.client,
    this.baseUrl =
        'http://192.168.1.82:8080/api', // Android emulator can access host v
  });

  Future<UserModel> registerUser(RegistrationRequestModel request) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/users/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 201) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        return UserModel.fromJson(jsonResponse); // Data is directly in response
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

  Future<UserModel> loginUser(String email, String password) async {
    final response = await client.post(
      Uri.parse('$baseUrl/users/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonResponse = json.decode(response.body);
      return UserModel.fromJson(jsonResponse); // Data is directly in response
    } else if (response.statusCode == 401) {
      throw Exception('Invalid credentials');
    } else {
      throw Exception('Login failed');
    }
  }

  Future<void> logoutUser() async {
    final response = await client.post(
      Uri.parse('$baseUrl/users/logout'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Logout failed');
    }
  }

  Future<UserModel?> getCurrentUser() async {
    // TODO: Implement when profile endpoint is available in backend
    return null;
  }
}
