import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';

class ActivityImageLocalDataSource {
  final LocalDbService _localDbService;

  ActivityImageLocalDataSource(this._localDbService);

  Future<int> insertWorkoutImage(ActivityImageEntity image) {
    return _localDbService.insertWorkoutImage(image);
  }

  Future<List<ActivityImageEntity>> getWorkoutImages(int workoutId) {
    return _localDbService.getWorkoutImages(workoutId);
  }

  Future<ActivityImageEntity?> getWorkoutImage(int localImageId) {
    return _localDbService.getWorkoutImage(localImageId);
  }

  Future<List<ActivityImageEntity>> getImagesReadyForSync(
    int userId,
    DateTime now,
  ) {
    return _localDbService.getImagesReadyForSync(userId, now);
  }

  Future<void> markImageUploading(int localImageId) {
    return _localDbService.markImageUploading(localImageId);
  }

  Future<void> markImageWaitingForActivitySync(int localImageId) {
    return _localDbService.markImageWaitingForActivitySync(localImageId);
  }

  Future<void> markImageUploaded({
    required int localImageId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) {
    return _localDbService.markImageUploaded(
      localImageId: localImageId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
      s3Key: s3Key,
    );
  }

  Future<void> markImageRetrying({
    required int localImageId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) {
    return _localDbService.markImageRetrying(
      localImageId: localImageId,
      error: error,
      nextRetryAt: nextRetryAt,
      retryCount: retryCount,
    );
  }

  Future<void> markImageFailed({
    required int localImageId,
    required String error,
  }) {
    return _localDbService.markImageFailed(
      localImageId: localImageId,
      error: error,
    );
  }

  Future<void> markImageDeleteQueued(int localImageId) {
    return _localDbService.markImageDeleteQueued(localImageId);
  }

  Future<void> markImageReplaceQueued(int localImageId) {
    return _localDbService.markImageReplaceQueued(localImageId);
  }

  Future<void> markReplaceQueuedImagesDeleteQueued(int workoutId) {
    return _localDbService.markReplaceQueuedImagesDeleteQueued(workoutId);
  }

  Future<void> markImageDeleting(int localImageId) {
    return _localDbService.markImageDeleting(localImageId);
  }

  Future<void> markImageDeleted(int localImageId) {
    return _localDbService.markImageDeleted(localImageId);
  }

  Future<void> resetStaleUploadingImages(DateTime staleBefore) {
    return _localDbService.resetStaleUploadingImages(staleBefore);
  }

  Future<void> updateRemoteImageUrl({
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
  }) {
    return _localDbService.updateRemoteImageUrl(
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
    );
  }

  Future<void> updateRemoteImageMetadata({
    required int localImageId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) {
    return _localDbService.updateRemoteImageMetadata(
      localImageId: localImageId,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
      s3Key: s3Key,
    );
  }
}
