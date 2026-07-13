import 'dart:convert';
import 'dart:io';

import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';

class ActivityImageUploadIntent {
  final int? imageId;
  final String clientImageId;
  final String key;
  final String? uploadUrl;
  final String? url;
  final DateTime? urlExpiresAt;
  final bool alreadyUploaded;

  const ActivityImageUploadIntent({
    this.imageId,
    required this.clientImageId,
    required this.key,
    this.uploadUrl,
    this.url,
    this.urlExpiresAt,
    this.alreadyUploaded = false,
  });
}

class RemoteActivityImage {
  final int id;
  final String clientImageId;
  final String key;
  final String url;
  final DateTime? urlExpiresAt;
  final String contentType;
  final int sizeBytes;

  const RemoteActivityImage({
    required this.id,
    required this.clientImageId,
    required this.key,
    required this.url,
    this.urlExpiresAt,
    required this.contentType,
    required this.sizeBytes,
  });
}

class ActivityImageRemoteDataSource {
  final AppHttpClient _httpClient;
  final AuthenticatedRequestExecutor _authenticatedRequests;

  ActivityImageRemoteDataSource({
    required AppHttpClient httpClient,
    required AuthenticatedRequestExecutor authenticatedRequests,
  }) : _httpClient = httpClient,
       _authenticatedRequests = authenticatedRequests;

  Future<ActivityImageUploadIntent> requestUploadUrl({
    required int remoteActivityId,
    required ActivityImageEntity image,
  }) async {
    final response = await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => _httpClient.post(
            AppConfig.getUrl('/activities/$remoteActivityId/images/upload-url'),
            headers: {'Content-Type': 'application/json', ...authHeaders},
            body: jsonEncode(_imageRequestBody(image)),
            maxRetries: 0,
          ),
    );

    final data = _decodeDataObject(response.body, 'upload URL');
    return ActivityImageUploadIntent(
      imageId:
          _readOptionalInt(data, 'imageId') ?? _readOptionalInt(data, 'id'),
      clientImageId: _readString(data, 'clientImageId'),
      key: _readString(data, 'key'),
      uploadUrl: _readOptionalString(data, 'uploadUrl'),
      url: _readOptionalString(data, 'url'),
      urlExpiresAt: _readOptionalDateTime(data, 'urlExpiresAt'),
      alreadyUploaded: data['alreadyUploaded'] == true,
    );
  }

  Future<void> uploadToS3({
    required String uploadUrl,
    required String localPath,
    required String contentType,
  }) async {
    final bytes = await File(localPath).readAsBytes();
    await _httpClient.put(
      uploadUrl,
      headers: {'Content-Type': contentType},
      body: bytes,
      maxRetries: 0,
    );
  }

  Future<RemoteActivityImage> confirmUpload({
    required int remoteActivityId,
    required ActivityImageEntity image,
    required String key,
  }) async {
    final response = await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => _httpClient.post(
            AppConfig.getUrl('/activities/$remoteActivityId/images/confirm'),
            headers: {'Content-Type': 'application/json', ...authHeaders},
            body: jsonEncode(_imageRequestBody(image, key: key)),
            maxRetries: 0,
          ),
    );

    final data = _decodeDataObject(response.body, 'confirm upload');
    return _mapRemoteActivityImage(data);
  }

  Future<List<RemoteActivityImage>> fetchImages({
    required int remoteActivityId,
  }) async {
    final response = await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => _httpClient.get(
            AppConfig.getUrl('/activities/$remoteActivityId/images'),
            headers: authHeaders,
          ),
    );

    final data = _decodeData(response.body, 'fetch images');
    if (data is! List) {
      throw Exception('Fetch images response data was not a list');
    }

    return data.map((item) {
      if (item is! Map<String, dynamic>) {
        throw Exception('Fetch images response contained an invalid item');
      }
      return _mapRemoteActivityImage(item);
    }).toList();
  }

  Future<void> deleteRemoteImage({
    required int remoteActivityId,
    required int remoteImageId,
  }) async {
    try {
      await _authenticatedRequests.execute(
        replayPolicy: AuthenticatedReplayPolicy.idempotent,
        request:
            (authHeaders) => _httpClient.delete(
              AppConfig.getUrl(
                '/activities/$remoteActivityId/images/$remoteImageId',
              ),
              headers: authHeaders,
              maxRetries: 0,
            ),
      );
    } on NotFoundException {
      return;
    }
  }

  Map<String, Object?> _imageRequestBody(
    ActivityImageEntity image, {
    String? key,
  }) {
    final body = <String, Object?>{
      'clientImageId': image.clientImageId,
      'contentType': image.contentType,
      'sizeBytes': image.sizeBytes,
      'checksumSha256': image.checksumSha256,
      'width': image.width,
      'height': image.height,
      'sortOrder': image.sortOrder,
      'caption': image.caption,
      if (key != null) 'key': key,
    };

    body.removeWhere((_, value) => value == null);
    return body;
  }

  dynamic _decodeData(String body, String operation) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid $operation response envelope');
    }

    if (decoded['status'] != 'success') {
      throw Exception('$operation response was not successful');
    }

    if (!decoded.containsKey('data')) {
      throw Exception('$operation response did not contain data');
    }

    return decoded['data'];
  }

  Map<String, dynamic> _decodeDataObject(String body, String operation) {
    final data = _decodeData(body, operation);
    if (data is! Map<String, dynamic>) {
      throw Exception('$operation response data was not an object');
    }

    return data;
  }

  RemoteActivityImage _mapRemoteActivityImage(Map<String, dynamic> data) {
    return RemoteActivityImage(
      id: _readInt(data, 'id'),
      clientImageId: _readString(data, 'clientImageId'),
      key: _readString(data, 'key'),
      url: _readString(data, 'url'),
      urlExpiresAt: _readOptionalDateTime(data, 'urlExpiresAt'),
      contentType: _readString(data, 'contentType'),
      sizeBytes: _readInt(data, 'sizeBytes'),
    );
  }

  String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }

    throw Exception('Response field "$key" was missing or invalid');
  }

  String? _readOptionalString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num) {
      return value.toInt();
    }

    throw Exception('Response field "$key" was missing or invalid');
  }

  int? _readOptionalInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is num ? value.toInt() : null;
  }

  DateTime? _readOptionalDateTime(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? DateTime.tryParse(value) : null;
  }
}
