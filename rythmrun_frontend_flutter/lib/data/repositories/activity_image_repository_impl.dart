import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' hide log;

import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/activity_image_file_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
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
  final UserScopeOperationGate? _operationGate;

  bool _isSyncingImages = false;

  ActivityImageRepositoryImpl({
    required ActivityImageLocalDataSource localDataSource,
    required ActivityImageRemoteDataSource remoteDataSource,
    required ActivityImageFileService fileService,
    required AuthRepository authRepository,
    required AuthLocalDataSource authLocalDataSource,
    required WorkoutLocalDataSource workoutLocalDataSource,
    Random? random,
    UserScopeOperationGate? operationGate,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _fileService = fileService,
       _authRepository = authRepository,
       _authLocalDataSource = authLocalDataSource,
       _workoutLocalDataSource = workoutLocalDataSource,
       _random = random ?? Random(),
       _operationGate = operationGate;

  @override
  Future<ActivityImageEntity> attachImage({
    required int localWorkoutId,
    required XFile image,
  }) {
    return _runForegroundOwnedOperation((userId) async {
      final workout = await _workoutLocalDataSource.getWorkoutFromLocalDatabase(
        localWorkoutId,
        userId: userId,
      );
      await _ensureOwnerStillCurrent(userId);
      if (workout == null) {
        throw Exception('Workout not found');
      }

      PreparedActivityImage? prepared;
      try {
        prepared = await _fileService.prepareImage(
          userId: userId,
          localWorkoutId: localWorkoutId,
          pickedFile: image,
        );
        await _ensureOwnerStillCurrent(userId);

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
        final localId = await _localDataSource.insertWorkoutImage(
          entity,
          userId: userId,
        );
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
    });
  }

  @override
  Future<void> deleteImage(int localImageId) {
    return _runForegroundOwnedOperation((userId) async {
      final image = await _getLocalImageOrThrow(userId, localImageId);
      await _ensureOwnerStillCurrent(userId);

      switch (image.status) {
        case ActivityImageSyncStatus.queued:
        case ActivityImageSyncStatus.waitingForActivitySync:
        case ActivityImageSyncStatus.retrying:
        case ActivityImageSyncStatus.failed:
          await _localDataSource.markImageDeleted(localImageId, userId: userId);
          await _deleteLocalFiles(image);
          return;
        case ActivityImageSyncStatus.deleted:
          return;
        case ActivityImageSyncStatus.uploading:
        case ActivityImageSyncStatus.uploaded:
        case ActivityImageSyncStatus.deleting:
        case ActivityImageSyncStatus.deleteQueued:
        case ActivityImageSyncStatus.replaceQueued:
          await _localDataSource.markImageDeleteQueued(
            localImageId,
            userId: userId,
          );
          unawaited(
            syncPendingImages().catchError((error) {
              log('Failed to sync activity image delete: $error');
            }),
          );
          return;
      }
    });
  }

  @override
  Future<ActivityImageEntity> replaceImage({
    required int oldLocalImageId,
    required XFile newImage,
  }) {
    return _runForegroundOwnedOperation((userId) async {
      final oldImage = await _getLocalImageOrThrow(userId, oldLocalImageId);

      PreparedActivityImage? prepared;
      try {
        prepared = await _fileService.prepareImage(
          userId: userId,
          localWorkoutId: oldImage.localWorkoutId,
          pickedFile: newImage,
        );
        await _ensureOwnerStillCurrent(userId);

        // File preparation can take long enough for background sync to move
        // the old row. Make the replacement decision from the latest state.
        final latestOldImage = await _getLocalImageOrThrow(
          userId,
          oldLocalImageId,
        );
        await _ensureOwnerStillCurrent(userId);

        final now = DateTime.now();
        final replacement = ActivityImageEntity(
          localWorkoutId: latestOldImage.localWorkoutId,
          remoteActivityId: latestOldImage.remoteActivityId,
          clientImageId: prepared.clientImageId,
          localPath: prepared.localPath,
          thumbnailPath: prepared.thumbnailPath,
          contentType: prepared.contentType,
          sizeBytes: prepared.sizeBytes,
          checksumSha256: prepared.checksumSha256,
          width: prepared.width,
          height: prepared.height,
          sortOrder: latestOldImage.sortOrder,
          caption: latestOldImage.caption,
          status: ActivityImageSyncStatus.queued,
          createdAt: now,
          updatedAt: now,
        );
        final localId = await _localDataSource.insertWorkoutImage(
          replacement,
          userId: userId,
        );
        final saved = replacement.copyWith(localId: localId);

        if (latestOldImage.status == ActivityImageSyncStatus.uploaded ||
            latestOldImage.status == ActivityImageSyncStatus.uploading) {
          await _localDataSource.markImageReplaceQueued(
            oldLocalImageId,
            userId: userId,
          );
        } else {
          await _localDataSource.markImageDeleted(
            oldLocalImageId,
            userId: userId,
          );
          await _deleteLocalFiles(latestOldImage);
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
    });
  }

  @override
  Future<List<ActivityImageEntity>> getImagesForWorkout(
    int localWorkoutId,
  ) async {
    final userId = await _requireCurrentUserId();
    final images = await _localDataSource.getWorkoutImages(
      localWorkoutId,
      userId: userId,
    );
    await _ensureOwnerStillCurrent(userId);
    return images;
  }

  @override
  Future<void> retryImage(int localImageId) {
    return _runForegroundOwnedOperation((userId) async {
      final image = await _getLocalImageOrThrow(userId, localImageId);
      await _ensureOwnerStillCurrent(userId);
      await _localDataSource.markImageRetrying(
        localImageId: localImageId,
        userId: userId,
        error: '',
        nextRetryAt: DateTime.now(),
        retryCount: image.retryCount,
      );

      unawaited(
        syncPendingImages().catchError((error) {
          log('Failed to sync activity image retry: $error');
        }),
      );
    });
  }

  @override
  Future<void> refreshRemoteImagesForWorkout(int localWorkoutId) {
    return _runForegroundOwnedOperation((userId) async {
      final workout = await _workoutLocalDataSource.getWorkoutFromLocalDatabase(
        localWorkoutId,
        userId: userId,
      );
      await _ensureOwnerStillCurrent(userId);
      final remoteActivityId = workout?.remoteActivityId;
      if (remoteActivityId == null) {
        return;
      }

      var authHeaders = await _authLocalDataSource.getAuthHeaders();
      await _ensureOwnerStillCurrent(userId);
      if (authHeaders == null) {
        return;
      }

      try {
        await _refreshRemoteImagesWithHeaders(
          userId: userId,
          localWorkoutId: localWorkoutId,
          remoteActivityId: remoteActivityId,
          authHeaders: authHeaders,
        );
      } on UnauthorizedException catch (_) {
        authHeaders = await _refreshAuthHeaders(userId);
        if (authHeaders == null) {
          return;
        }
        await _refreshRemoteImagesWithHeaders(
          userId: userId,
          localWorkoutId: localWorkoutId,
          remoteActivityId: remoteActivityId,
          authHeaders: authHeaders,
        );
      } on ForbiddenException catch (_) {
        authHeaders = await _refreshAuthHeaders(userId);
        if (authHeaders == null) {
          return;
        }
        await _refreshRemoteImagesWithHeaders(
          userId: userId,
          localWorkoutId: localWorkoutId,
          remoteActivityId: remoteActivityId,
          authHeaders: authHeaders,
        );
      }
    });
  }

  @override
  Future<void> syncPendingImages() async {
    if (_isSyncingImages) {
      return;
    }
    _isSyncingImages = true;
    UserScopeOperationLease? operationLease;

    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        return;
      }

      operationLease = _operationGate?.tryAcquire(userId);
      if (_operationGate != null && operationLease == null) {
        return;
      }
      await _ensureOwnerStillCurrent(userId);

      await _runImageJanitor(userId);

      final initialAuthHeaders = await _authLocalDataSource.getAuthHeaders();
      await _ensureOwnerStillCurrent(userId);
      if (initialAuthHeaders == null) {
        return;
      }
      var authHeaders = initialAuthHeaders;

      final images = await _localDataSource.getImagesReadyForSync(
        userId,
        DateTime.now(),
      );
      await _ensureOwnerStillCurrent(userId);

      for (final image in images) {
        await _ensureOwnerStillCurrent(userId);
        final nextAuthHeaders = await _syncImageWithAuthRetry(
          userId,
          image,
          authHeaders,
        );
        if (nextAuthHeaders == null) {
          return;
        }
        authHeaders = nextAuthHeaders;
      }
    } on _ActivityImageOwnerChangedException {
      // The original owner's row remains in its durable retryable state.
      return;
    } finally {
      _isSyncingImages = false;
      operationLease?.release();
    }
  }

  Future<Map<String, String>?> _syncImageWithAuthRetry(
    int userId,
    ActivityImageEntity image,
    Map<String, String> authHeaders,
  ) async {
    try {
      await _syncImage(userId, image, authHeaders);
      return authHeaders;
    } on _ActivityImageOwnerChangedException {
      return null;
    } on UnauthorizedException catch (_) {
      return _refreshAuthAndRetryImage(userId, image);
    } on ForbiddenException catch (_) {
      return _refreshAuthAndRetryImage(userId, image);
    } catch (error) {
      if (!await _isOwnerStillCurrent(userId)) {
        return null;
      }
      await _markRetryingOrFailed(userId, image, error);
      return authHeaders;
    }
  }

  Future<void> _runImageJanitor(int userId) async {
    await _localDataSource.resetStaleUploadingImages(
      userId,
      DateTime.now().subtract(const Duration(minutes: 15)),
    );

    final activeImages = await _localDataSource.getActiveImagesForJanitor(
      userId,
    );
    for (final image in activeImages) {
      final localImageId = image.localId;
      if (localImageId == null) {
        continue;
      }

      if (_isDeleteLikeStatus(image.status) &&
          (image.remoteActivityId == null || image.remoteImageId == null)) {
        await _ensureOwnerStillCurrent(userId);
        await _localDataSource.markImageDeleted(localImageId, userId: userId);
        await _deleteLocalFiles(image);
        continue;
      }

      if (!_isUploadLikeStatus(image.status)) {
        continue;
      }

      if (!await _fileService.exists(image.localPath)) {
        await _ensureOwnerStillCurrent(userId);
        if (image.remoteImageId != null) {
          continue;
        }
        await _localDataSource.markImageFailed(
          localImageId: localImageId,
          userId: userId,
          error: 'missing_local_file',
        );
      }
    }
  }

  Future<Map<String, String>?> _refreshAuthAndRetryImage(
    int userId,
    ActivityImageEntity image,
  ) async {
    Map<String, String>? refreshedAuthHeaders;
    try {
      refreshedAuthHeaders = await _refreshAuthHeaders(userId);
    } on _ActivityImageOwnerChangedException {
      return null;
    }
    if (refreshedAuthHeaders == null) {
      if (!await _isOwnerStillCurrent(userId)) {
        return null;
      }
      await _markRetryingOrFailed(userId, image, 'Auth refresh failed');
      return null;
    }

    try {
      await _syncImage(
        userId,
        image,
        refreshedAuthHeaders,
        alreadyClaimed: true,
      );
    } on _ActivityImageOwnerChangedException {
      return null;
    } catch (retryError) {
      if (!await _isOwnerStillCurrent(userId)) {
        return null;
      }
      await _markRetryingOrFailed(userId, image, retryError);
    }

    return refreshedAuthHeaders;
  }

  Future<void> _syncImage(
    int userId,
    ActivityImageEntity image,
    Map<String, String> authHeaders, {
    bool alreadyClaimed = false,
  }) async {
    if (image.status == ActivityImageSyncStatus.queued ||
        image.status == ActivityImageSyncStatus.waitingForActivitySync ||
        image.status == ActivityImageSyncStatus.retrying) {
      await _syncUpload(
        userId,
        image,
        authHeaders,
        alreadyClaimed: alreadyClaimed,
      );
    } else if (image.status == ActivityImageSyncStatus.deleteQueued) {
      await _syncDelete(
        userId,
        image,
        authHeaders,
        alreadyClaimed: alreadyClaimed,
      );
    }
  }

  Future<void> _syncUpload(
    int userId,
    ActivityImageEntity image,
    Map<String, String> authHeaders, {
    bool alreadyClaimed = false,
  }) async {
    final localImageId = _requireLocalImageId(image);
    final workout = await _workoutLocalDataSource.getWorkoutFromLocalDatabase(
      image.localWorkoutId,
      userId: userId,
    );
    await _ensureOwnerStillCurrent(userId);

    if (workout == null) {
      throw const _PermanentImageSyncException('Local workout not found');
    }

    final remoteActivityId = workout.remoteActivityId;
    if (remoteActivityId == null) {
      await _localDataSource.markImageWaitingForActivitySyncIfReady(
        localImageId,
        userId: userId,
      );
      return;
    }

    if (!await _fileService.exists(image.localPath)) {
      await _ensureOwnerStillCurrent(userId);
      if (image.remoteImageId != null) {
        return;
      }
      throw const _PermanentImageSyncException('Local image file is missing');
    }

    if (!alreadyClaimed) {
      final didStartUpload = await _localDataSource.markImageUploadingIfReady(
        localImageId,
        userId: userId,
      );
      if (!didStartUpload) {
        return;
      }
    }
    await _ensureOwnerStillCurrent(userId);

    final intent = await _remoteDataSource.requestUploadUrl(
      remoteActivityId: remoteActivityId,
      image: image,
      authHeaders: authHeaders,
    );
    await _ensureOwnerStillCurrent(userId);

    if (intent.alreadyUploaded) {
      final finalStatus = await _recordAlreadyUploadedIntent(
        userId: userId,
        image: image,
        remoteActivityId: remoteActivityId,
        intent: intent,
      );
      await _finishPostUploadState(
        userId: userId,
        localImageId: localImageId,
        localWorkoutId: image.localWorkoutId,
        finalStatus: finalStatus,
        authHeaders: authHeaders,
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
    await _ensureOwnerStillCurrent(userId);

    final remoteImage = await _remoteDataSource.confirmUpload(
      remoteActivityId: remoteActivityId,
      image: image,
      key: intent.key,
      authHeaders: authHeaders,
    );
    await _ensureOwnerStillCurrent(userId);

    final finalStatus = await _localDataSource.recordImageUploadResult(
      localImageId: localImageId,
      userId: userId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImage.id,
      remoteUrl: remoteImage.url,
      remoteUrlExpiresAt: remoteImage.urlExpiresAt,
      s3Key: remoteImage.key,
    );
    await _finishPostUploadState(
      userId: userId,
      localImageId: localImageId,
      localWorkoutId: image.localWorkoutId,
      finalStatus: finalStatus,
      authHeaders: authHeaders,
    );
  }

  Future<void> _syncDelete(
    int userId,
    ActivityImageEntity image,
    Map<String, String> authHeaders, {
    bool alreadyClaimed = false,
  }) async {
    final localImageId = _requireLocalImageId(image);
    final remoteActivityId = image.remoteActivityId;
    final remoteImageId = image.remoteImageId;

    if (remoteActivityId == null || remoteImageId == null) {
      await _ensureOwnerStillCurrent(userId);
      await _localDataSource.markImageDeleted(localImageId, userId: userId);
      await _deleteLocalFiles(image);
      return;
    }

    if (!alreadyClaimed) {
      await _ensureOwnerStillCurrent(userId);
      final didClaimDelete = await _localDataSource.markImageDeleting(
        localImageId,
        userId: userId,
      );
      if (!didClaimDelete) {
        return;
      }
    }
    await _ensureOwnerStillCurrent(userId);
    try {
      await _remoteDataSource.deleteRemoteImage(
        remoteActivityId: remoteActivityId,
        remoteImageId: remoteImageId,
        authHeaders: authHeaders,
      );
    } on NotFoundException {
      // Idempotent success: the remote image is already absent.
    }
    await _ensureOwnerStillCurrent(userId);
    await _localDataSource.markImageDeleted(localImageId, userId: userId);
    await _deleteLocalFiles(image);
  }

  Future<ActivityImageSyncStatus?> _recordAlreadyUploadedIntent({
    required int userId,
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

    return _localDataSource.recordImageUploadResult(
      localImageId: localImageId,
      userId: userId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: intent.urlExpiresAt,
      s3Key: intent.key,
    );
  }

  Future<void> _finishPostUploadState({
    required int userId,
    required int localImageId,
    required int localWorkoutId,
    required ActivityImageSyncStatus? finalStatus,
    required Map<String, String> authHeaders,
  }) async {
    await _ensureOwnerStillCurrent(userId);
    if (finalStatus == ActivityImageSyncStatus.deleteQueued) {
      final latest = await _localDataSource.getWorkoutImage(
        localImageId,
        userId: userId,
      );
      await _ensureOwnerStillCurrent(userId);
      if (latest != null) {
        await _syncDelete(userId, latest, authHeaders);
      }
      return;
    }

    if (finalStatus == ActivityImageSyncStatus.uploaded) {
      await _localDataSource.markReplaceQueuedImagesDeleteQueued(
        localWorkoutId,
        userId: userId,
      );
    }
  }

  Future<void> _refreshRemoteImagesWithHeaders({
    required int userId,
    required int localWorkoutId,
    required int remoteActivityId,
    required Map<String, String> authHeaders,
  }) async {
    final localImages = await _localDataSource.getWorkoutImages(
      localWorkoutId,
      userId: userId,
    );
    await _ensureOwnerStillCurrent(userId);
    final remoteImages = await _remoteDataSource.fetchImages(
      remoteActivityId: remoteActivityId,
      authHeaders: authHeaders,
    );
    await _ensureOwnerStillCurrent(userId);

    for (final remoteImage in remoteImages) {
      final byRemoteId = localImages.where(
        (image) => image.remoteImageId == remoteImage.id,
      );
      if (byRemoteId.isNotEmpty) {
        final localImageId = byRemoteId.first.localId;
        final latest =
            localImageId == null
                ? null
                : await _localDataSource.getWorkoutImage(
                  localImageId,
                  userId: userId,
                );
        await _ensureOwnerStillCurrent(userId);
        if (latest != null && _canApplyRemoteRefresh(latest.status)) {
          await _localDataSource.updateRemoteImageUrl(
            userId: userId,
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

      final latest = await _localDataSource.getWorkoutImage(
        localImageId,
        userId: userId,
      );
      await _ensureOwnerStillCurrent(userId);
      if (latest == null || !_canApplyRemoteRefresh(latest.status)) {
        continue;
      }

      await _localDataSource.updateRemoteImageMetadata(
        localImageId: localImageId,
        userId: userId,
        remoteActivityId: remoteActivityId,
        remoteImageId: remoteImage.id,
        remoteUrl: remoteImage.url,
        remoteUrlExpiresAt: remoteImage.urlExpiresAt,
        s3Key: remoteImage.key,
      );
    }
  }

  Future<void> _markRetryingOrFailed(
    int userId,
    ActivityImageEntity image,
    Object error,
  ) async {
    final localImageId = image.localId;
    if (localImageId == null) {
      return;
    }

    final latest = await _localDataSource.getWorkoutImage(
      localImageId,
      userId: userId,
    );
    await _ensureOwnerStillCurrent(userId);
    if (latest != null && _isDeleteLikeStatus(latest.status)) {
      if (latest.remoteActivityId == null || latest.remoteImageId == null) {
        await _localDataSource.markImageDeleted(localImageId, userId: userId);
        await _deleteLocalFiles(latest);
        return;
      }

      final retryCount = latest.retryCount + 1;
      await _localDataSource.markImageDeleteQueuedRetrying(
        localImageId: localImageId,
        userId: userId,
        error: error.toString(),
        nextRetryAt: DateTime.now().add(_retryDelayWithJitter(retryCount)),
        retryCount: retryCount,
      );
      return;
    }

    if (image.status == ActivityImageSyncStatus.deleteQueued ||
        image.status == ActivityImageSyncStatus.deleting) {
      final retryCount = image.retryCount + 1;
      await _localDataSource.markImageDeleteQueuedRetrying(
        localImageId: localImageId,
        userId: userId,
        error: error.toString(),
        nextRetryAt: DateTime.now().add(_retryDelayWithJitter(retryCount)),
        retryCount: retryCount,
      );
      return;
    }

    if (_isPermanentFailure(error)) {
      await _localDataSource.markImageFailed(
        localImageId: localImageId,
        userId: userId,
        error: error.toString(),
      );
      return;
    }

    final retryCount = image.retryCount + 1;
    await _localDataSource.markImageRetrying(
      localImageId: localImageId,
      userId: userId,
      error: error.toString(),
      nextRetryAt: DateTime.now().add(_retryDelayWithJitter(retryCount)),
      retryCount: retryCount,
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

  bool _isUploadLikeStatus(ActivityImageSyncStatus status) {
    return status == ActivityImageSyncStatus.queued ||
        status == ActivityImageSyncStatus.waitingForActivitySync ||
        status == ActivityImageSyncStatus.uploading ||
        status == ActivityImageSyncStatus.retrying;
  }

  bool _isDeleteLikeStatus(ActivityImageSyncStatus status) {
    return status == ActivityImageSyncStatus.deleteQueued ||
        status == ActivityImageSyncStatus.deleting ||
        status == ActivityImageSyncStatus.deleted ||
        status == ActivityImageSyncStatus.replaceQueued;
  }

  Future<void> _deleteLocalFiles(ActivityImageEntity image) async {
    await _fileService.deleteIfExists(image.localPath);
    await _fileService.deleteIfExists(image.thumbnailPath);
  }

  Future<ActivityImageEntity> _getLocalImageOrThrow(
    int userId,
    int localImageId,
  ) async {
    final image = await _localDataSource.getWorkoutImage(
      localImageId,
      userId: userId,
    );
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

  Future<int> _requireCurrentUserId() async {
    final userId = await _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    return userId;
  }

  Future<bool> _isOwnerStillCurrent(int userId) async {
    return await _getCurrentUserId() == userId;
  }

  Future<void> _ensureOwnerStillCurrent(int userId) async {
    if (!await _isOwnerStillCurrent(userId)) {
      throw const _ActivityImageOwnerChangedException();
    }
  }

  Future<T> _runForegroundOwnedOperation<T>(
    Future<T> Function(int userId) action,
  ) async {
    final userId = await _requireCurrentUserId();
    final operationLease = _operationGate?.tryAcquire(userId);
    if (_operationGate != null && operationLease == null) {
      throw const _ActivityImageOwnerChangedException();
    }

    try {
      await _ensureOwnerStillCurrent(userId);
      return await action(userId);
    } finally {
      operationLease?.release();
    }
  }

  Future<Map<String, String>?> _refreshAuthHeaders(int userId) async {
    try {
      await _ensureOwnerStillCurrent(userId);
      await _authRepository.refreshToken();
      await _ensureOwnerStillCurrent(userId);
      final authHeaders = await _authLocalDataSource.getAuthHeaders();
      await _ensureOwnerStillCurrent(userId);
      return authHeaders;
    } catch (error) {
      if (error is _ActivityImageOwnerChangedException) {
        rethrow;
      }
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

class _ActivityImageOwnerChangedException implements Exception {
  const _ActivityImageOwnerChangedException();

  @override
  String toString() => 'The active account changed during image work';
}
