import 'dart:developer' as developer;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/core/utils/ensure_type_helper.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/avatar_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';

class AvatarRepositoryImpl implements AvatarRepository {
  static const int _maxAvatarBytes = 10 * 1024 * 1024;
  static const Map<String, String> _extensionByMimeType = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };

  final AvatarRemoteDataSource remoteDataSource;
  final AuthRepository authRepository;
  final AppHttpClient httpClient;
  final UserScopeOperationGate? operationGate;

  AvatarRepositoryImpl(
    this.remoteDataSource,
    this.authRepository,
    this.httpClient, {
    this.operationGate,
  });

  @override
  Future<AvatarUploadResult> uploadAvatar(XFile image) async {
    developer.log('[pfp] Starting avatar upload', name: 'AvatarRepository');

    final owner = await authRepository.getCurrentUser();
    if (owner == null) {
      developer.log('[pfp] ERROR: Not authenticated', name: 'AvatarRepository');
      throw Exception('Not authenticated');
    }
    final ownerId = EnsureTypeHelper.ensureInt(owner.id);
    final operationLease = operationGate?.tryAcquire(ownerId);
    if (operationGate != null && operationLease == null) {
      throw Exception('Account cleanup is in progress');
    }

    try {
      var mimeType = image.mimeType ?? lookupMimeType(image.path);
      if (mimeType == null) {
        throw Exception('Avatar must be a JPEG, PNG, or WebP image');
      }
      mimeType = mimeType.split(';').first.trim().toLowerCase();
      final extension = _extensionByMimeType[mimeType];
      if (extension == null) {
        throw Exception('Avatar must be a JPEG, PNG, or WebP image');
      }

      late final int declaredSizeBytes;
      try {
        declaredSizeBytes = await image.length();
      } catch (_) {
        throw Exception('Unable to read avatar image');
      }
      if (declaredSizeBytes < 1 || declaredSizeBytes > _maxAvatarBytes) {
        throw Exception('Avatar must be between 1 byte and 10 MiB');
      }

      late final List<int> fileBytes;
      try {
        fileBytes = await image.readAsBytes();
      } catch (_) {
        throw Exception('Unable to read avatar image');
      }
      if (fileBytes.length != declaredSizeBytes) {
        throw Exception('Avatar changed while it was being prepared');
      }

      final authorization = await remoteDataSource.getUploadUrl(
        extension,
        mimeType,
        declaredSizeBytes,
      );

      await httpClient.postMultipart(
        authorization.uploadUri.toString(),
        fields: authorization.fields,
        fileField: 'file',
        fileBytes: fileBytes,
        filename: 'avatar.$extension',
        maxRetries: 0,
      );

      if ((await authRepository.getCurrentUser())?.id != owner.id) {
        throw Exception('The active account changed during avatar upload');
      }
      await remoteDataSource.confirmUpload(authorization.key, mimeType);

      developer.log('[pfp] Avatar upload completed', name: 'AvatarRepository');
      return AvatarUploadResult(key: authorization.key, mimeType: mimeType);
    } catch (_) {
      developer.log('[pfp] Avatar upload failed', name: 'AvatarRepository');
      throw Exception('Failed to upload avatar. Please try again.');
    } finally {
      operationLease?.release();
    }
  }
}
