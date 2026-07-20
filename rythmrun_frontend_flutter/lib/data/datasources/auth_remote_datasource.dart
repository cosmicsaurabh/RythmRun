import 'dart:convert';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';

import '../../core/config/app_config.dart';
import '../../core/config/api_endpoints.dart';
import '../../core/network/http_client.dart';
import '../../core/services/google_identity_service.dart';
import '../models/auth_response_model.dart';
import '../models/registration_request_model.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  final AppHttpClient _httpClient;
  final String Function(String endpoint) _resolveEndpoint;

  AuthRemoteDataSource({
    required AppHttpClient httpClient,
    String Function(String endpoint)? resolveEndpoint,
  }) : _httpClient = httpClient,
       _resolveEndpoint = resolveEndpoint ?? AppConfig.getUrl;

  Future<AuthResponseModel> registerUser(
    RegistrationRequestModel request,
  ) async {
    final response = await _httpClient.post(
      _resolveEndpoint(ApiEndpoints.register),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(request.toJson()),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return AuthResponseModel.fromJson(jsonResponse);
  }

  Future<AuthResponseModel> loginUser(String email, String password) async {
    final response = await _httpClient.post(
      _resolveEndpoint(ApiEndpoints.login),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': email, 'password': password}),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return AuthResponseModel.fromJson(jsonResponse);
  }

  /// Exchanges a short-lived Google ID token for the app's normal backend
  /// access/refresh token pair. Identity tokens are never sent over cleartext.
  Future<AuthResponseModel> loginWithGoogle(String idToken) async {
    final endpoint = _resolveEndpoint(ApiEndpoints.googleAuth);
    if (Uri.tryParse(endpoint)?.scheme.toLowerCase() != 'https') {
      throw const GoogleIdentityException(
        'Google sign-in requires a secure HTTPS backend connection.',
      );
    }

    final response = await _httpClient.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'idToken': idToken}),
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
      _resolveEndpoint(ApiEndpoints.logout),
      headers: headers,
      maxRetries: 0,
    );
  }

  /// Refresh access token using the provided refresh token
  Future<AuthResponseModel> refreshToken(String refreshToken) async {
    final response = await _httpClient.post(
      _resolveEndpoint(ApiEndpoints.refreshToken),
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
      _resolveEndpoint(ApiEndpoints.changePassword),
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
      _resolveEndpoint(ApiEndpoints.me),
      headers: headers,
    );

    return response.statusCode == 200;
  }

  /// Fetch the server's current safe user.
  ///
  /// [verifySession] deliberately returns only a boolean, so it cannot observe
  /// server-side state changes. This parses the body instead, which is what
  /// lets the client notice an email that was verified on another device.
  Future<UserModel> fetchCurrentUser(Map<String, String> authHeaders) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...authHeaders,
    };

    final response = await _httpClient.get(
      _resolveEndpoint(ApiEndpoints.me),
      headers: headers,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return UserModel.fromJson(jsonResponse);
  }

  /// Ask the backend to re-send the verification email for the signed-in user.
  /// The server throttles this and answers generically.
  Future<void> resendVerificationEmail(Map<String, String> authHeaders) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...authHeaders,
    };

    await _httpClient.post(
      _resolveEndpoint(ApiEndpoints.resendVerification),
      headers: headers,
      maxRetries: 0,
    );
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
      _resolveEndpoint(ApiEndpoints.profile),
      headers: headers,
      body: json.encode({'firstname': firstName, 'lastname': lastName}),
      maxRetries: 0,
    );

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return UserModel.fromJson(jsonResponse);
  }
}
