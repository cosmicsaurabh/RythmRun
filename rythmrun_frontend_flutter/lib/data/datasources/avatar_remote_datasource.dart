import 'dart:convert';
import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';

abstract class AvatarRemoteDataSource {
  Future<AvatarUploadAuthorization> getUploadUrl(
    String ext,
    String contentType,
    int sizeBytes,
  );
  Future<void> confirmUpload(String key, String contentType);
}

class AvatarUploadAuthorization {
  final Uri uploadUri;
  final String key;
  final Map<String, String> fields;

  const AvatarUploadAuthorization({
    required this.uploadUri,
    required this.key,
    required this.fields,
  });

  factory AvatarUploadAuthorization.fromJson(Map<String, dynamic> json) {
    final uploadUrl = json['uploadUrl'];
    final uploadMethod = json['uploadMethod'];
    final key = json['key'];
    final rawFields = json['fields'];

    if (uploadUrl is! String ||
        uploadMethod is! String ||
        uploadMethod.toUpperCase() != 'POST' ||
        key is! String ||
        key.isEmpty ||
        rawFields is! Map) {
      throw const FormatException('Invalid avatar upload authorization');
    }

    final uploadUri = Uri.tryParse(uploadUrl);
    if (uploadUri == null ||
        uploadUri.scheme != 'https' ||
        uploadUri.host.isEmpty) {
      throw const FormatException('Invalid avatar upload destination');
    }

    final fields = <String, String>{};
    for (final entry in rawFields.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid avatar upload fields');
      }
      fields[entry.key as String] = entry.value as String;
    }

    if (fields['key'] != key) {
      throw const FormatException('Avatar upload key mismatch');
    }

    return AvatarUploadAuthorization(
      uploadUri: uploadUri,
      key: key,
      fields: Map.unmodifiable(fields),
    );
  }
}

class AvatarRemoteDataSourceImpl implements AvatarRemoteDataSource {
  final AppHttpClient httpClient;
  final AuthenticatedRequestExecutor authenticatedRequests;

  AvatarRemoteDataSourceImpl(this.httpClient, this.authenticatedRequests);

  @override
  Future<AvatarUploadAuthorization> getUploadUrl(
    String ext,
    String contentType,
    int sizeBytes,
  ) async {
    final response = await authenticatedRequests.execute(
      request:
          (authHeaders) => httpClient.post(
            AppConfig.getUrl('/avatar/upload-url'),
            headers: {'Content-Type': 'application/json', ...authHeaders},
            body: jsonEncode({
              'ext': ext,
              'contentType': contentType,
              'sizeBytes': sizeBytes,
            }),
            maxRetries: 0,
          ),
    );

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return AvatarUploadAuthorization.fromJson(decoded);
    } on FormatException {
      throw Exception('Invalid response from avatar upload endpoint');
    }
  }

  @override
  Future<void> confirmUpload(String key, String contentType) async {
    await authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => httpClient.post(
            AppConfig.getUrl('/avatar/confirm'),
            headers: {'Content-Type': 'application/json', ...authHeaders},
            body: jsonEncode({'key': key, 'contentType': contentType}),
            maxRetries: 0,
          ),
    );
  }
}
