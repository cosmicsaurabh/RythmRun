import 'dart:convert';
import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';

abstract class AvatarRemoteDataSource {
  Future<Map<String, dynamic>> getUploadUrl(
    String ext,
    String contentType,
    String token,
  );
  Future<void> confirmUpload(String key, String contentType, String token);
}

class AvatarRemoteDataSourceImpl implements AvatarRemoteDataSource {
  final AppHttpClient httpClient;

  AvatarRemoteDataSourceImpl(this.httpClient);

  @override
  Future<Map<String, dynamic>> getUploadUrl(
    String ext,
    String contentType,
    String token,
  ) async {
    final response = await httpClient.post(
      AppConfig.getUrl('/avatar/upload-url'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'ext': ext, 'contentType': contentType}),
    );

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw Exception('Invalid JSON response from upload URL endpoint: $e');
    }
  }

  @override
  Future<void> confirmUpload(
    String key,
    String contentType,
    String token,
  ) async {
    await httpClient.post(
      AppConfig.getUrl('/avatar/confirm'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'key': key, 'contentType': contentType}),
    );
  }
}
