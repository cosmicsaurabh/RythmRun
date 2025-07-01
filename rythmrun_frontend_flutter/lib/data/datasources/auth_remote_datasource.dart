import 'dart:convert';
import '../../core/config/app_config.dart';
import '../../core/config/api_endpoints.dart';
import '../../core/network/http_client.dart';
import '../models/user_model.dart';
import '../models/auth_response_model.dart';
import '../models/registration_request_model.dart';

class AuthRemoteDataSource {
  final AppHttpClient _httpClient;

  AuthRemoteDataSource({AppHttpClient? httpClient})
    : _httpClient = httpClient ?? AppHttpClient();

  Future<AuthResponseModel> registerUser(
    RegistrationRequestModel request,
  ) async {
    try {
      final response = await _httpClient.post(
        AppConfig.getUrl(ApiEndpoints.register),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      final Map<String, dynamic> jsonResponse = json.decode(response.body);
      return AuthResponseModel.fromJson(jsonResponse);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<AuthResponseModel> loginUser(String email, String password) async {
    try {
      final response = await _httpClient.post(
        AppConfig.getUrl(ApiEndpoints.login),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': email, 'password': password}),
      );

      final Map<String, dynamic> jsonResponse = json.decode(response.body);
      return AuthResponseModel.fromJson(jsonResponse);
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

      await _httpClient.post(
        AppConfig.getUrl(ApiEndpoints.logout),
        headers: headers,
      );
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<UserModel?> getCurrentUser() async {
    return null;
  }

  /// Refresh access token using the provided refresh token
  Future<AuthResponseModel> refreshToken(String refreshToken) async {
    try {
      final response = await _httpClient.post(
        AppConfig.getUrl(ApiEndpoints.refreshToken),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refreshToken': refreshToken}),
      );

      final Map<String, dynamic> jsonResponse = json.decode(response.body);
      return AuthResponseModel.fromJson(jsonResponse);
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
