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
  Future<Uri> getReadUrl();
}

class AvatarUploadAuthorization {
  final Uri uploadUri;
  final String key;
  final Map<String, String> requiredHeaders;

  const AvatarUploadAuthorization({
    required this.uploadUri,
    required this.key,
    required this.requiredHeaders,
  });

  factory AvatarUploadAuthorization.fromJson(Map<String, dynamic> json) {
    final uploadUrl = json['uploadUrl'];
    final uploadMethod = json['uploadMethod'];
    final key = json['key'];
    final rawRequiredHeaders = json['requiredHeaders'];

    if (uploadUrl is! String ||
        uploadMethod is! String ||
        uploadMethod.toUpperCase() != 'PUT' ||
        key is! String ||
        key.isEmpty ||
        rawRequiredHeaders is! Map) {
      throw const FormatException('Invalid avatar upload authorization');
    }

    final uploadUri = Uri.tryParse(uploadUrl);
    if (uploadUri == null ||
        uploadUri.scheme != 'https' ||
        uploadUri.host.isEmpty) {
      throw const FormatException('Invalid avatar upload destination');
    }

    final requiredHeaders = <String, String>{};
    for (final entry in rawRequiredHeaders.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid avatar upload headers');
      }
      requiredHeaders[entry.key as String] = entry.value as String;
    }

    final contentType = requiredHeaders['Content-Type'];
    if (contentType == null || contentType.isEmpty) {
      throw const FormatException('Avatar upload content type is missing');
    }
    final contentLength = int.tryParse(requiredHeaders['Content-Length'] ?? '');
    if (contentLength == null || contentLength < 1) {
      throw const FormatException('Avatar upload content length is missing');
    }

    return AvatarUploadAuthorization(
      uploadUri: uploadUri,
      key: key,
      requiredHeaders: Map.unmodifiable(requiredHeaders),
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

  @override
  Future<Uri> getReadUrl() async {
    final response = await authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => httpClient.get(
            AppConfig.getUrl('/avatar/read-url'),
            headers: authHeaders,
          ),
    );

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }

      final rawUrl = decoded['url'];
      if (rawUrl is! String) {
        throw const FormatException('Avatar read URL is missing');
      }
      final url = Uri.tryParse(rawUrl);
      if (url == null || url.scheme != 'https' || url.host.isEmpty) {
        throw const FormatException('Invalid avatar read URL');
      }
      return url;
    } on FormatException {
      throw Exception('Invalid response from avatar read endpoint');
    }
  }
}
