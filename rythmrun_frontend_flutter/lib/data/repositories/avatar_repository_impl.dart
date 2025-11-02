import 'dart:developer' as developer;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/avatar_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';

class AvatarRepositoryImpl implements AvatarRepository {
  final AvatarRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;
  final AppHttpClient httpClient;

  AvatarRepositoryImpl(
    this.remoteDataSource,
    this.localDataSource,
    this.httpClient,
  );

  @override
  Future<AvatarUploadResult> uploadAvatar(XFile image) async {
    developer.log('[pfp] Starting avatar upload', name: 'AvatarRepository');

    final token = await localDataSource.getAccessToken();
    if (token == null) {
      developer.log('[pfp] ERROR: Not authenticated', name: 'AvatarRepository');
      throw Exception('Not authenticated');
    }

    developer.log(
      '[pfp] Reading image file: ${image.path}',
      name: 'AvatarRepository',
    );
    final fileBytes = await image.readAsBytes();
    developer.log(
      '[pfp] Image file size: ${fileBytes.length} bytes',
      name: 'AvatarRepository',
    );

    // Use XFile's mimeType if available, otherwise fallback to lookupMimeType
    var mimeType = image.mimeType ?? lookupMimeType(image.path);
    if (mimeType == null) {
      developer.log(
        '[pfp] ERROR: Unable to determine MIME type',
        name: 'AvatarRepository',
      );
      throw Exception('Unable to determine MIME type for image');
    }
    // Normalize mimeType - remove charset and extra whitespace to ensure exact match with S3 signature
    final originalMimeType = mimeType;
    mimeType = mimeType.split(';').first.trim();
    final ext = image.path.split('.').last.toLowerCase();

    developer.log(
      '[pfp] Image details - Original MIME: $originalMimeType, Normalized MIME: $mimeType, Extension: $ext',
      name: 'AvatarRepository',
    );

    try {
      // 1. Get upload URL - use the exact mimeType that will be sent to S3
      developer.log(
        '[pfp] Requesting upload URL from server (ext: $ext, contentType: $mimeType)',
        name: 'AvatarRepository',
      );
      final uploadUrlData = await remoteDataSource.getUploadUrl(
        ext,
        mimeType,
        token,
      );
      final uploadUrl = uploadUrlData['uploadUrl'] as String;
      final key = uploadUrlData['key'] as String;
      developer.log(
        '[pfp] Received upload URL - Key: -:), URL length: ${uploadUrl.length}',
        name: 'AvatarRepository',
      );

      if (uploadUrl.isEmpty) {
        developer.log(
          '[pfp] ERROR: Invalid upload URL received from server',
          name: 'AvatarRepository',
        );
        throw Exception('Invalid upload URL received from server');
      }

      // 2. Upload to S3 using presigned URL
      // Critical: The Content-Type header MUST match exactly what was used to sign the presigned URL
      // S3 presigned URLs are very strict - headers must match the signature exactly
      developer.log(
        '[pfp] Uploading to S3 with Content-Type: $mimeType',
        name: 'AvatarRepository',
      );
      final uploadResponse = await httpClient.put(
        uploadUrl,
        headers: {'Content-Type': mimeType},
        body: fileBytes,
      );

      developer.log(
        '[pfp] S3 upload response status: ${uploadResponse.statusCode}',
        name: 'AvatarRepository',
      );
      if (uploadResponse.statusCode != 200 &&
          uploadResponse.statusCode != 204) {
        // S3 error responses contain XML with details about what went wrong
        developer.log(
          '[pfp] ERROR: S3 upload failed - Status: ${uploadResponse.statusCode}, Body: ${uploadResponse.body}',
          name: 'AvatarRepository',
        );
        throw Exception(
          'Failed to upload image to S3: ${uploadResponse.statusCode} - ${uploadResponse.body}',
        );
      }
      developer.log('[pfp] S3 upload successful', name: 'AvatarRepository');

      // 3. Confirm upload
      developer.log(
        '[pfp] Confirming upload with server (key: $key)',
        name: 'AvatarRepository',
      );
      await remoteDataSource.confirmUpload(key, mimeType, token);
      developer.log(
        '[pfp] Upload confirmed successfully',
        name: 'AvatarRepository',
      );

      developer.log(
        '[pfp] Avatar upload completed successfully - Key: -:), MIME: $mimeType',
        name: 'AvatarRepository',
      );
      return AvatarUploadResult(key: key, mimeType: mimeType);
    } catch (e) {
      developer.log(
        '[pfp] ERROR: Failed to upload avatar - $e',
        name: 'AvatarRepository',
      );
      throw Exception('Failed to upload avatar: $e');
    }
  }
}
