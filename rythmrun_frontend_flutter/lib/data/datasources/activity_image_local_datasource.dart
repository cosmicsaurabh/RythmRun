import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';

class ActivityImageLocalDataSource {
  final LocalDbService _localDbService;

  ActivityImageLocalDataSource(this._localDbService);

  Future<int> insertWorkoutImage(
    ActivityImageEntity image, {
    required int userId,
  }) {
    return _localDbService.insertWorkoutImage(image, userId: userId);
  }

  Future<List<ActivityImageEntity>> getWorkoutImages(
    int workoutId, {
    required int userId,
  }) {
    return _localDbService.getWorkoutImages(workoutId, userId: userId);
  }

  Future<ActivityImageEntity?> getWorkoutImage(
    int localImageId, {
    required int userId,
  }) {
    return _localDbService.getWorkoutImage(localImageId, userId: userId);
  }

  Future<List<ActivityImageEntity>> getImagesReadyForSync(
    int userId,
    DateTime now,
  ) {
    return _localDbService.getImagesReadyForSync(userId, now);
  }

  Future<List<ActivityImageEntity>> getActiveImagesForJanitor(int userId) {
    return _localDbService.getActiveImagesForJanitor(userId);
  }

  Future<bool> markImageUploadingIfReady(
    int localImageId, {
    required int userId,
  }) {
    return _localDbService.markImageUploadingIfReady(
      localImageId,
      userId: userId,
    );
  }

  Future<bool> markImageWaitingForActivitySyncIfReady(
    int localImageId, {
    required int userId,
  }) {
    return _localDbService.markImageWaitingForActivitySyncIfReady(
      localImageId,
      userId: userId,
    );
  }

  Future<ActivityImageSyncStatus?> recordImageUploadResult({
    required int localImageId,
    required int userId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) {
    return _localDbService.recordImageUploadResult(
      localImageId: localImageId,
      userId: userId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
      s3Key: s3Key,
    );
  }

  Future<void> markImageRetrying({
    required int localImageId,
    required int userId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) {
    return _localDbService.markImageRetrying(
      localImageId: localImageId,
      userId: userId,
      error: error,
      nextRetryAt: nextRetryAt,
      retryCount: retryCount,
    );
  }

  Future<void> markImageDeleteQueuedRetrying({
    required int localImageId,
    required int userId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) {
    return _localDbService.markImageDeleteQueuedRetrying(
      localImageId: localImageId,
      userId: userId,
      error: error,
      nextRetryAt: nextRetryAt,
      retryCount: retryCount,
    );
  }

  Future<void> markImageFailed({
    required int localImageId,
    required int userId,
    required String error,
  }) {
    return _localDbService.markImageFailed(
      localImageId: localImageId,
      userId: userId,
      error: error,
    );
  }

  Future<void> markImageDeleteQueued(int localImageId, {required int userId}) {
    return _localDbService.markImageDeleteQueued(localImageId, userId: userId);
  }

  Future<void> markImageReplaceQueued(int localImageId, {required int userId}) {
    return _localDbService.markImageReplaceQueued(localImageId, userId: userId);
  }

  Future<void> markReplaceQueuedImagesDeleteQueued(
    int workoutId, {
    required int userId,
  }) {
    return _localDbService.markReplaceQueuedImagesDeleteQueued(
      workoutId,
      userId: userId,
    );
  }

  Future<bool> markImageDeleting(int localImageId, {required int userId}) {
    return _localDbService.markImageDeleting(localImageId, userId: userId);
  }

  Future<void> markImageDeleted(int localImageId, {required int userId}) {
    return _localDbService.markImageDeleted(localImageId, userId: userId);
  }

  Future<void> resetStaleUploadingImages(int userId, DateTime staleBefore) {
    return _localDbService.resetStaleUploadingImages(userId, staleBefore);
  }

  Future<void> updateRemoteImageUrl({
    required int userId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
  }) {
    return _localDbService.updateRemoteImageUrl(
      userId: userId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
    );
  }

  Future<void> updateRemoteImageMetadata({
    required int localImageId,
    required int userId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) {
    return _localDbService.updateRemoteImageMetadata(
      localImageId: localImageId,
      userId: userId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
      s3Key: s3Key,
    );
  }
}
