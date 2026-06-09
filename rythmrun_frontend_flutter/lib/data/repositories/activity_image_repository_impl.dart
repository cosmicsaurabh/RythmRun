import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' hide log;

import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/activity_image_file_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/ensure_type_helper.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_image_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_image_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/workout_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';

class ActivityImageRepositoryImpl implements ActivityImageRepository {
  final ActivityImageLocalDataSource _localDataSource;
  final ActivityImageRemoteDataSource _remoteDataSource;
  final ActivityImageFileService _fileService;
  final AuthRepository _authRepository;
  final AuthLocalDataSource _authLocalDataSource;
  final WorkoutLocalDataSource _workoutLocalDataSource;
  final Random _random;

  bool _isSyncingImages = false;

  ActivityImageRepositoryImpl({
    required ActivityImageLocalDataSource localDataSource,
    required ActivityImageRemoteDataSource remoteDataSource,
    required ActivityImageFileService fileService,
    required AuthRepository authRepository,
    required AuthLocalDataSource authLocalDataSource,
    required WorkoutLocalDataSource workoutLocalDataSource,
    Random? random,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _fileService = fileService,
       _authRepository = authRepository,
       _authLocalDataSource = authLocalDataSource,
       _workoutLocalDataSource = workoutLocalDataSource,
       _random = random ?? Random();

  @override
  Future<ActivityImageEntity> attachImage({
    required int localWorkoutId,
    required XFile image,
  }) async {
    final userId = await _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    PreparedActivityImage? prepared;
    try {
      prepared = await _fileService.prepareImage(
        userId: userId,
        localWorkoutId: localWorkoutId,
        pickedFile: image,
      );

      final now = DateTime.now();
      final entity = ActivityImageEntity(
        localWorkoutId: localWorkoutId,
        clientImageId: prepared.clientImageId,
        localPath: prepared.localPath,
        thumbnailPath: prepared.thumbnailPath,
        contentType: prepared.contentType,
        sizeBytes: prepared.sizeBytes,
        checksumSha256: prepared.checksumSha256,
        width: prepared.width,
        height: prepared.height,
        status: ActivityImageSyncStatus.queued,
        createdAt: now,
        updatedAt: now,
      );
      final localId = await _localDataSource.insertWorkoutImage(entity);
      final saved = entity.copyWith(localId: localId);

      unawaited(
        syncPendingImages().catchError((error) {
          log('Failed to sync activity image after attach: $error');
        }),
      );

      return saved;
    } catch (_) {
      if (prepared != null) {
        await _fileService.deleteIfExists(prepared.localPath);
        await _fileService.deleteIfExists(prepared.thumbnailPath);
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteImage(int localImageId) async {
    final image = await _getLocalImageOrThrow(localImageId);

    switch (image.status) {
      case ActivityImageSyncStatus.queued:
      case ActivityImageSyncStatus.waitingForActivitySync:
      case ActivityImageSyncStatus.retrying:
      case ActivityImageSyncStatus.failed:
        await _localDataSource.markImageDeleted(localImageId);
        await _deleteLocalFiles(image);
        return;
      case ActivityImageSyncStatus.deleted:
        return;
      case ActivityImageSyncStatus.uploading:
      case ActivityImageSyncStatus.uploaded:
      case ActivityImageSyncStatus.deleting:
      case ActivityImageSyncStatus.deleteQueued:
      case ActivityImageSyncStatus.replaceQueued:
        await _localDataSource.markImageDeleteQueued(localImageId);
        unawaited(
          syncPendingImages().catchError((error) {
            log('Failed to sync activity image delete: $error');
          }),
        );
        return;
    }
  }

  @override
  Future<ActivityImageEntity> replaceImage({
    required int oldLocalImageId,
    required XFile newImage,
  }) async {
    final oldImage = await _getLocalImageOrThrow(oldLocalImageId);
    final userId = await _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    PreparedActivityImage? prepared;
    try {
      prepared = await _fileService.prepareImage(
        userId: userId,
        localWorkoutId: oldImage.localWorkoutId,
        pickedFile: newImage,
      );

      final now = DateTime.now();
      final replacement = ActivityImageEntity(
        localWorkoutId: oldImage.localWorkoutId,
        remoteActivityId: oldImage.remoteActivityId,
        clientImageId: prepared.clientImageId,
        localPath: prepared.localPath,
        thumbnailPath: prepared.thumbnailPath,
        contentType: prepared.contentType,
        sizeBytes: prepared.sizeBytes,
        checksumSha256: prepared.checksumSha256,
        width: prepared.width,
        height: prepared.height,
        sortOrder: oldImage.sortOrder,
        caption: oldImage.caption,
        status: ActivityImageSyncStatus.queued,
        createdAt: now,
        updatedAt: now,
      );
      final localId = await _localDataSource.insertWorkoutImage(replacement);
      final saved = replacement.copyWith(localId: localId);

      if (oldImage.status == ActivityImageSyncStatus.uploaded ||
          oldImage.status == ActivityImageSyncStatus.uploading) {
        await _localDataSource.markImageReplaceQueued(oldLocalImageId);
      } else {
        await _localDataSource.markImageDeleted(oldLocalImageId);
        await _deleteLocalFiles(oldImage);
      }

      unawaited(
        syncPendingImages().catchError((error) {
          log('Failed to sync activity image replacement: $error');
        }),
      );

      return saved;
    } catch (_) {
      if (prepared != null) {
        await _fileService.deleteIfExists(prepared.localPath);
        await _fileService.deleteIfExists(prepared.thumbnailPath);
      }
      rethrow;
    }
  }

  @override
  Future<List<ActivityImageEntity>> getImagesForWorkout(
    int localWorkoutId,
  ) async {
    return _localDataSource.getWorkoutImages(localWorkoutId);
  }

  @override
  Future<void> retryImage(int localImageId) async {
    final image = await _getLocalImageOrThrow(localImageId);
    await _localDataSource.markImageRetrying(
      localImageId: localImageId,
      error: '',
      nextRetryAt: DateTime.now(),
      retryCount: image.retryCount,
    );

    unawaited(
      syncPendingImages().catchError((error) {
        log('Failed to sync activity image retry: $error');
      }),
    );
  }

  @override
  Future<void> refreshRemoteImagesForWorkout(int localWorkoutId) async {
    final workout = await _workoutLocalDataSource.getWorkoutFromLocalDatabase(
      localWorkoutId,
    );
    final remoteActivityId = workout?.remoteActivityId;
    if (remoteActivityId == null) {
      return;
    }

    var authHeaders = await _authLocalDataSource.getAuthHeaders();
    if (authHeaders == null) {
      return;
    }

    try {
      await _refreshRemoteImagesWithHeaders(
        localWorkoutId: localWorkoutId,
        remoteActivityId: remoteActivityId,
        authHeaders: authHeaders,
      );
    } on UnauthorizedException catch (_) {
      authHeaders = await _refreshAuthHeaders();
      if (authHeaders == null) {
        return;
      }
      await _refreshRemoteImagesWithHeaders(
        localWorkoutId: localWorkoutId,
        remoteActivityId: remoteActivityId,
        authHeaders: authHeaders,
      );
    } on ForbiddenException catch (_) {
      authHeaders = await _refreshAuthHeaders();
      if (authHeaders == null) {
        return;
      }
      await _refreshRemoteImagesWithHeaders(
        localWorkoutId: localWorkoutId,
        remoteActivityId: remoteActivityId,
        authHeaders: authHeaders,
      );
    }
  }

  @override
  Future<void> syncPendingImages() async {
    if (_isSyncingImages) {
      return;
    }
    _isSyncingImages = true;

    try {
      await _localDataSource.resetStaleUploadingImages(
        DateTime.now().subtract(const Duration(minutes: 15)),
      );

      final userId = await _getCurrentUserId();
      if (userId == null) {
        return;
      }

      final initialAuthHeaders = await _authLocalDataSource.getAuthHeaders();
      if (initialAuthHeaders == null) {
        return;
      }
      var authHeaders = initialAuthHeaders;

      final images = await _localDataSource.getImagesReadyForSync(
        userId,
        DateTime.now(),
      );

      for (final image in images) {
        final nextAuthHeaders = await _syncImageWithAuthRetry(
          image,
          authHeaders,
        );
        if (nextAuthHeaders == null) {
          return;
        }
        authHeaders = nextAuthHeaders;
      }
    } finally {
      _isSyncingImages = false;
    }
  }

  Future<Map<String, String>?> _syncImageWithAuthRetry(
    ActivityImageEntity image,
    Map<String, String> authHeaders,
  ) async {
    try {
      await _syncImage(image, authHeaders);
      return authHeaders;
    } on UnauthorizedException catch (_) {
      return _refreshAuthAndRetryImage(image);
    } on ForbiddenException catch (_) {
      return _refreshAuthAndRetryImage(image);
    } catch (error) {
      await _markRetryingOrFailed(image, error);
      return authHeaders;
    }
  }

  Future<Map<String, String>?> _refreshAuthAndRetryImage(
    ActivityImageEntity image,
  ) async {
    final refreshedAuthHeaders = await _refreshAuthHeaders();
    if (refreshedAuthHeaders == null) {
      await _markImageFailedIfPossible(image, 'Auth refresh failed');
      return null;
    }

    try {
      await _syncImage(image, refreshedAuthHeaders);
    } catch (retryError) {
      await _markRetryingOrFailed(image, retryError);
    }

    return refreshedAuthHeaders;
  }

  Future<void> _syncImage(
    ActivityImageEntity image,
    Map<String, String> authHeaders,
  ) async {
    if (image.status == ActivityImageSyncStatus.queued ||
        image.status == ActivityImageSyncStatus.waitingForActivitySync ||
        image.status == ActivityImageSyncStatus.retrying) {
      await _syncUpload(image, authHeaders);
    } else if (image.status == ActivityImageSyncStatus.deleteQueued) {
      await _syncDelete(image, authHeaders);
    }
  }

  Future<void> _syncUpload(
    ActivityImageEntity image,
    Map<String, String> authHeaders,
  ) async {
    final localImageId = _requireLocalImageId(image);
    final workout = await _workoutLocalDataSource.getWorkoutFromLocalDatabase(
      image.localWorkoutId,
    );

    if (workout == null) {
      throw const _PermanentImageSyncException('Local workout not found');
    }

    final remoteActivityId = workout.remoteActivityId;
    if (remoteActivityId == null) {
      await _localDataSource.markImageWaitingForActivitySync(localImageId);
      return;
    }

    if (!await _fileService.exists(image.localPath)) {
      if (image.remoteImageId != null) {
        return;
      }
      throw const _PermanentImageSyncException('Local image file is missing');
    }

    await _localDataSource.markImageUploading(localImageId);

    final intent = await _remoteDataSource.requestUploadUrl(
      remoteActivityId: remoteActivityId,
      image: image,
      authHeaders: authHeaders,
    );

    if (intent.alreadyUploaded) {
      await _markUploadedFromIntent(
        image: image,
        remoteActivityId: remoteActivityId,
        intent: intent,
      );
      await _localDataSource.markReplaceQueuedImagesDeleteQueued(
        image.localWorkoutId,
      );
      return;
    }

    final uploadUrl = intent.uploadUrl;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const _PermanentImageSyncException(
        'Upload URL response did not include uploadUrl',
      );
    }

    await _remoteDataSource.uploadToS3(
      uploadUrl: uploadUrl,
      localPath: image.localPath,
      contentType: image.contentType,
    );

    final remoteImage = await _remoteDataSource.confirmUpload(
      remoteActivityId: remoteActivityId,
      image: image,
      key: intent.key,
      authHeaders: authHeaders,
    );

    await _localDataSource.markImageUploaded(
      localImageId: localImageId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImage.id,
      remoteUrl: remoteImage.url,
      remoteUrlExpiresAt: remoteImage.urlExpiresAt,
      s3Key: remoteImage.key,
    );
    await _localDataSource.markReplaceQueuedImagesDeleteQueued(
      image.localWorkoutId,
    );
  }

  Future<void> _syncDelete(
    ActivityImageEntity image,
    Map<String, String> authHeaders,
  ) async {
    final localImageId = _requireLocalImageId(image);
    final remoteActivityId = image.remoteActivityId;
    final remoteImageId = image.remoteImageId;

    if (remoteActivityId == null || remoteImageId == null) {
      await _localDataSource.markImageDeleted(localImageId);
      await _deleteLocalFiles(image);
      return;
    }

    await _localDataSource.markImageDeleting(localImageId);
    await _remoteDataSource.deleteRemoteImage(
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      authHeaders: authHeaders,
    );
    await _localDataSource.markImageDeleted(localImageId);
    await _deleteLocalFiles(image);
  }

  Future<void> _markUploadedFromIntent({
    required ActivityImageEntity image,
    required int remoteActivityId,
    required ActivityImageUploadIntent intent,
  }) async {
    final localImageId = _requireLocalImageId(image);
    final remoteImageId = intent.imageId;
    final remoteUrl = intent.url;
    if (remoteImageId == null || remoteUrl == null) {
      throw const _PermanentImageSyncException(
        'Already uploaded response did not include remote image metadata',
      );
    }

    await _localDataSource.markImageUploaded(
      localImageId: localImageId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: intent.urlExpiresAt,
      s3Key: intent.key,
    );
  }

  Future<void> _refreshRemoteImagesWithHeaders({
    required int localWorkoutId,
    required int remoteActivityId,
    required Map<String, String> authHeaders,
  }) async {
    final localImages = await _localDataSource.getWorkoutImages(localWorkoutId);
    final remoteImages = await _remoteDataSource.fetchImages(
      remoteActivityId: remoteActivityId,
      authHeaders: authHeaders,
    );

    for (final remoteImage in remoteImages) {
      final byRemoteId = localImages.where(
        (image) => image.remoteImageId == remoteImage.id,
      );
      if (byRemoteId.isNotEmpty) {
        final localImage = byRemoteId.first;
        if (_canApplyRemoteRefresh(localImage.status)) {
          await _localDataSource.updateRemoteImageUrl(
            remoteImageId: remoteImage.id,
            remoteUrl: remoteImage.url,
            remoteUrlExpiresAt: remoteImage.urlExpiresAt,
          );
        }
        continue;
      }

      final byClientImageId = localImages.where(
        (image) =>
            image.clientImageId == remoteImage.clientImageId &&
            image.remoteImageId == null,
      );
      if (byClientImageId.isEmpty) {
        continue;
      }

      final localImage = byClientImageId.first;
      final localImageId = localImage.localId;
      if (localImageId == null || !_canApplyRemoteRefresh(localImage.status)) {
        continue;
      }

      await _localDataSource.updateRemoteImageMetadata(
        localImageId: localImageId,
        remoteActivityId: remoteActivityId,
        remoteImageId: remoteImage.id,
        remoteUrl: remoteImage.url,
        remoteUrlExpiresAt: remoteImage.urlExpiresAt,
        s3Key: remoteImage.key,
      );
    }
  }

  Future<void> _markRetryingOrFailed(
    ActivityImageEntity image,
    Object error,
  ) async {
    final localImageId = image.localId;
    if (localImageId == null) {
      return;
    }

    if (_isPermanentFailure(error)) {
      await _localDataSource.markImageFailed(
        localImageId: localImageId,
        error: error.toString(),
      );
      return;
    }

    final retryCount = image.retryCount + 1;
    await _localDataSource.markImageRetrying(
      localImageId: localImageId,
      error: error.toString(),
      nextRetryAt: DateTime.now().add(_retryDelayWithJitter(retryCount)),
      retryCount: retryCount,
    );
  }

  Future<void> _markImageFailedIfPossible(
    ActivityImageEntity image,
    String error,
  ) async {
    final localImageId = image.localId;
    if (localImageId == null) {
      return;
    }

    await _localDataSource.markImageFailed(
      localImageId: localImageId,
      error: error,
    );
  }

  bool _isPermanentFailure(Object error) {
    if (error is _PermanentImageSyncException ||
        error is ActivityImageFileException ||
        error is FileSystemException) {
      return true;
    }

    if (error is HttpStatusException) {
      return error.statusCode == 400 ||
          error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 404;
    }

    return false;
  }

  Duration _retryDelayWithJitter(int retryCount) {
    final baseDelay = _retryDelayFor(retryCount);
    final jitterMs = (baseDelay.inMilliseconds * 0.2).round();
    if (jitterMs <= 0) {
      return baseDelay;
    }

    final offset = _random.nextInt(jitterMs * 2 + 1) - jitterMs;
    final delayedMs = max(1000, baseDelay.inMilliseconds + offset);
    return Duration(milliseconds: delayedMs);
  }

  Duration _retryDelayFor(int retryCount) {
    if (retryCount <= 0) return const Duration(seconds: 30);
    if (retryCount == 1) return const Duration(minutes: 2);
    if (retryCount == 2) return const Duration(minutes: 5);
    if (retryCount == 3) return const Duration(minutes: 15);
    if (retryCount == 4) return const Duration(hours: 1);
    return const Duration(hours: 6);
  }

  bool _canApplyRemoteRefresh(ActivityImageSyncStatus status) {
    return status == ActivityImageSyncStatus.uploaded ||
        status == ActivityImageSyncStatus.waitingForActivitySync ||
        status == ActivityImageSyncStatus.failed;
  }

  Future<void> _deleteLocalFiles(ActivityImageEntity image) async {
    await _fileService.deleteIfExists(image.localPath);
    await _fileService.deleteIfExists(image.thumbnailPath);
  }

  Future<ActivityImageEntity> _getLocalImageOrThrow(int localImageId) async {
    final image = await _localDataSource.getWorkoutImage(localImageId);
    if (image == null) {
      throw Exception('Activity image not found');
    }

    return image;
  }

  int _requireLocalImageId(ActivityImageEntity image) {
    final localImageId = image.localId;
    if (localImageId == null) {
      throw const _PermanentImageSyncException(
        'Local image ID is required for sync',
      );
    }

    return localImageId;
  }

  Future<int?> _getCurrentUserId() async {
    final user = await _authRepository.getCurrentUser();
    return user != null ? EnsureTypeHelper.ensureInt(user.id) : null;
  }

  Future<Map<String, String>?> _refreshAuthHeaders() async {
    try {
      await _authRepository.refreshToken();
      return await _authLocalDataSource.getAuthHeaders();
    } catch (error) {
      log('Failed to refresh auth token during image sync: $error');
      return null;
    }
  }
}

class _PermanentImageSyncException implements Exception {
  final String message;

  const _PermanentImageSyncException(this.message);

  @override
  String toString() => message;
}
