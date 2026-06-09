enum ActivityImageSyncStatus {
  queued,
  waitingForActivitySync,
  uploading,
  uploaded,
  retrying,
  failed,
  deleteQueued,
  deleting,
  deleted,
  replaceQueued,
}

ActivityImageSyncStatus activityImageSyncStatusFromName(String? value) {
  return ActivityImageSyncStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ActivityImageSyncStatus.failed,
  );
}

class ActivityImageEntity {
  final int? localId;
  final int localWorkoutId;
  final int? remoteActivityId;
  final int? remoteImageId;
  final String clientImageId;
  final String localPath;
  final String? thumbnailPath;
  final String? remoteUrl;
  final DateTime? remoteUrlExpiresAt;
  final String? s3Key;
  final String contentType;
  final int sizeBytes;
  final String? checksumSha256;
  final int? width;
  final int? height;
  final int sortOrder;
  final String? caption;
  final ActivityImageSyncStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime? nextRetryAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ActivityImageEntity({
    this.localId,
    required this.localWorkoutId,
    this.remoteActivityId,
    this.remoteImageId,
    required this.clientImageId,
    required this.localPath,
    this.thumbnailPath,
    this.remoteUrl,
    this.remoteUrlExpiresAt,
    this.s3Key,
    required this.contentType,
    required this.sizeBytes,
    this.checksumSha256,
    this.width,
    this.height,
    this.sortOrder = 0,
    this.caption,
    required this.status,
    this.retryCount = 0,
    this.lastError,
    this.nextRetryAt,
    required this.createdAt,
    required this.updatedAt,
  });

  ActivityImageEntity copyWith({
    int? localId,
    int? localWorkoutId,
    int? remoteActivityId,
    int? remoteImageId,
    String? clientImageId,
    String? localPath,
    String? thumbnailPath,
    String? remoteUrl,
    DateTime? remoteUrlExpiresAt,
    String? s3Key,
    String? contentType,
    int? sizeBytes,
    String? checksumSha256,
    int? width,
    int? height,
    int? sortOrder,
    String? caption,
    ActivityImageSyncStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? nextRetryAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ActivityImageEntity(
      localId: localId ?? this.localId,
      localWorkoutId: localWorkoutId ?? this.localWorkoutId,
      remoteActivityId: remoteActivityId ?? this.remoteActivityId,
      remoteImageId: remoteImageId ?? this.remoteImageId,
      clientImageId: clientImageId ?? this.clientImageId,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt ?? this.remoteUrlExpiresAt,
      s3Key: s3Key ?? this.s3Key,
      contentType: contentType ?? this.contentType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      width: width ?? this.width,
      height: height ?? this.height,
      sortOrder: sortOrder ?? this.sortOrder,
      caption: caption ?? this.caption,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
