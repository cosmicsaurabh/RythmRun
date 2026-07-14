import 'dart:convert';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';

import '../../core/config/app_config.dart';
import '../../core/config/api_endpoints.dart';
import '../../core/network/http_client.dart';
import '../models/auth_response_model.dart';
import '../models/registration_request_model.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  final AppHttpClient _httpClient;

  AuthRemoteDataSource({required AppHttpClient httpClient})
    : _httpClient = httpClient;

  Future<AuthResponseModel> registerUser(
    RegistrationRequestModel request,
  ) async {
    final response = await _httpClient.post(
      AppConfig.getUrl(ApiEndpoints.register),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(request.toJson()),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return AuthResponseModel.fromJson(jsonResponse);
  }

  Future<AuthResponseModel> loginUser(String email, String password) async {
    final response = await _httpClient.post(
      AppConfig.getUrl(ApiEndpoints.login),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': email, 'password': password}),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return AuthResponseModel.fromJson(jsonResponse);
  }

  Future<void> logoutUser(Map<String, String>? authHeaders) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...?authHeaders,
    };

    await _httpClient.post(
      AppConfig.getUrl(ApiEndpoints.logout),
      headers: headers,
      maxRetries: 0,
    );
  }

  /// Refresh access token using the provided refresh token
  Future<AuthResponseModel> refreshToken(String refreshToken) async {
    final response = await _httpClient.post(
      AppConfig.getUrl(ApiEndpoints.refreshToken),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'refreshToken': refreshToken}),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return AuthResponseModel.fromJson(jsonResponse);
  }

  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
    Map<String, String> authHeaders,
  ) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...authHeaders,
    };

    final response = await _httpClient.put(
      AppConfig.getUrl(ApiEndpoints.changePassword),
      headers: headers,
      body: json.encode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return ChangePasswordResponseModel.fromJson(jsonResponse);
  }

  /// Verify session with backend server
  Future<bool> verifySession(Map<String, String> authHeaders) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...authHeaders,
    };

    final response = await _httpClient.get(
      AppConfig.getUrl(ApiEndpoints.me),
      headers: headers,
    );

    return response.statusCode == 200;
  }

  /// Update first/last name and return the server's updated safe user.
  Future<UserModel> updateProfile(
    String firstName,
    String lastName,
    Map<String, String> authHeaders,
  ) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...authHeaders,
    };

    final response = await _httpClient.put(
      AppConfig.getUrl(ApiEndpoints.profile),
      headers: headers,
      body: json.encode({'firstname': firstName, 'lastname': lastName}),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return UserModel.fromJson(jsonResponse);
  }
}
