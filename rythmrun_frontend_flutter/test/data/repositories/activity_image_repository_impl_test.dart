import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/services/activity_image_file_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_image_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_image_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/workout_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/activity_image_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/registration_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';

void main() {
  group('ActivityImageRepositoryImpl', () {
    late List<String> events;
    late FakeActivityImageLocalDataSource localDataSource;
    late FakeActivityImageRemoteDataSource remoteDataSource;
    late FakeActivityImageFileService fileService;
    late FakeAuthRepository authRepository;
    late FakeAuthLocalDataSource authLocalDataSource;
    late FakeWorkoutLocalDataSource workoutLocalDataSource;
    late ActivityImageRepositoryImpl repository;

    const userId = 1;
    const localWorkoutId = 42;
    const remoteActivityId = 900;
    const remoteImageId = 700;
    const clientImageId = 'img_client_123456';
    const appPrivatePath =
        '/app/documents/activity_images/1/42/originals/img_client_123456.jpg';
    const thumbnailPath =
        '/app/documents/activity_images/1/42/thumbnails/img_client_123456.jpg';

    setUp(() {
      events = <String>[];
      localDataSource = FakeActivityImageLocalDataSource(events);
      remoteDataSource = FakeActivityImageRemoteDataSource(events);
      fileService =
          FakeActivityImageFileService(events)
            ..preparedImage = const PreparedActivityImage(
              clientImageId: clientImageId,
              localPath: appPrivatePath,
              thumbnailPath: thumbnailPath,
              contentType: 'image/jpeg',
              sizeBytes: 1024,
              width: 800,
              height: 600,
              checksumSha256:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            )
            ..existingPaths.add(appPrivatePath);
      authRepository = FakeAuthRepository(
        currentUser: const UserEntity(
          id: '$userId',
          firstName: 'Test',
          lastName: 'User',
          email: 'test@example.com',
        ),
      );
      authLocalDataSource = FakeAuthLocalDataSource();
      workoutLocalDataSource =
          FakeWorkoutLocalDataSource()
            ..workouts[localWorkoutId] = _workout(
              localWorkoutId: localWorkoutId,
              remoteActivityId: remoteActivityId,
              userId: userId,
            );
      repository = ActivityImageRepositoryImpl(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
        fileService: fileService,
        authRepository: authRepository,
        authLocalDataSource: authLocalDataSource,
        workoutLocalDataSource: workoutLocalDataSource,
        random: Random(0),
      );
    });

    test(
      'attach inserts a local row before any network upload starts',
      () async {
        await repository.attachImage(
          localWorkoutId: localWorkoutId,
          image: XFile(
            '/tmp/image_picker/cache/picker_temp.jpg',
            mimeType: 'image/jpeg',
          ),
        );
        await _pumpMicrotasks();

        expect(localDataSource.insertedImages, hasLength(1));
        expect(
          localDataSource.insertedImages.single.status,
          ActivityImageSyncStatus.queued,
        );
        expect(localDataSource.insertedImages.single.localPath, appPrivatePath);
        expect(
          localDataSource.insertedImages.single.localPath,
          isNot('/tmp/image_picker/cache/picker_temp.jpg'),
        );
        expect(
          events.indexOf('insert'),
          lessThan(events.indexOf('request-url')),
        );
      },
    );

    test('sync changes status from queued to uploading to uploaded', () async {
      localDataSource.addImage(
        _image(
          localId: 1,
          localWorkoutId: localWorkoutId,
          clientImageId: clientImageId,
          localPath: appPrivatePath,
          thumbnailPath: thumbnailPath,
          status: ActivityImageSyncStatus.queued,
        ),
      );

      await repository.syncPendingImages();

      expect(
        localDataSource.statusEvents,
        containsAllInOrder([
          ActivityImageSyncStatus.uploading,
          ActivityImageSyncStatus.uploaded,
        ]),
      );
      expect(
        localDataSource.images[1]!.status,
        ActivityImageSyncStatus.uploaded,
      );
      expect(localDataSource.images[1]!.remoteActivityId, remoteActivityId);
      expect(localDataSource.images[1]!.remoteImageId, remoteImageId);
    });

    test(
      'user-scope suspension waits for in-flight image sync and blocks new sync',
      () async {
        final gate = UserScopeOperationGate()..activate(userId);
        repository = ActivityImageRepositoryImpl(
          localDataSource: localDataSource,
          remoteDataSource: remoteDataSource,
          fileService: fileService,
          authRepository: authRepository,
          authLocalDataSource: authLocalDataSource,
          workoutLocalDataSource: workoutLocalDataSource,
          random: Random(0),
          operationGate: gate,
        );
        localDataSource.addImage(
          _image(
            localId: 1,
            localWorkoutId: localWorkoutId,
            clientImageId: clientImageId,
            localPath: appPrivatePath,
            thumbnailPath: thumbnailPath,
            status: ActivityImageSyncStatus.queued,
          ),
        );
        final reachedConfirm = Completer<void>();
        final allowConfirm = Completer<void>();
        remoteDataSource.beforeConfirm = () async {
          if (!reachedConfirm.isCompleted) {
            reachedConfirm.complete();
          }
          await allowConfirm.future;
        };

        final sync = repository.syncPendingImages();
        await reachedConfirm.future;

        var didDrain = false;
        final drain = gate.suspendAndDrain().then((_) {
          didDrain = true;
        });
        await _pumpMicrotasks();

        expect(didDrain, isFalse);
        expect(gate.tryAcquire(userId), isNull);

        allowConfirm.complete();
        await sync;
        await drain;
        expect(didDrain, isTrue);

        localDataSource.addImage(
          _image(
            localId: 2,
            localWorkoutId: localWorkoutId,
            clientImageId: 'img_client_second',
            localPath: appPrivatePath,
            thumbnailPath: thumbnailPath,
            status: ActivityImageSyncStatus.queued,
          ),
        );
        final requestCountBeforeSuspendedSync =
            remoteDataSource.requestUploadUrlCount;

        await repository.syncPendingImages();

        expect(
          remoteDataSource.requestUploadUrlCount,
          requestCountBeforeSuspendedSync,
        );

        gate.activate(userId);
        await repository.syncPendingImages();
        expect(
          remoteDataSource.requestUploadUrlCount,
          greaterThan(requestCountBeforeSuspendedSync),
        );
      },
    );

    test('network error changes uploading to retrying', () async {
      remoteDataSource.uploadError = Exception('network down');
      localDataSource.addImage(
        _image(
          localId: 1,
          localWorkoutId: localWorkoutId,
          clientImageId: clientImageId,
          localPath: appPrivatePath,
          thumbnailPath: thumbnailPath,
          status: ActivityImageSyncStatus.queued,
        ),
      );

      await repository.syncPendingImages();

      expect(
        localDataSource.statusEvents,
        containsAllInOrder([
          ActivityImageSyncStatus.uploading,
          ActivityImageSyncStatus.retrying,
        ]),
      );
      expect(
        localDataSource.images[1]!.status,
        ActivityImageSyncStatus.retrying,
      );
      expect(localDataSource.images[1]!.retryCount, 1);
      expect(localDataSource.images[1]!.lastError, contains('network down'));
    });

    test(
      'delete during in-flight upload queues remote delete after confirm',
      () async {
        localDataSource.addImage(
          _image(
            localId: 1,
            localWorkoutId: localWorkoutId,
            clientImageId: clientImageId,
            localPath: appPrivatePath,
            thumbnailPath: thumbnailPath,
            status: ActivityImageSyncStatus.queued,
          ),
        );
        remoteDataSource.beforeConfirm = () async {
          await localDataSource.markImageDeleteQueued(1);
        };

        await repository.syncPendingImages();

        expect(
          localDataSource.statusEvents,
          containsAllInOrder([
            ActivityImageSyncStatus.uploading,
            ActivityImageSyncStatus.deleteQueued,
            ActivityImageSyncStatus.deleting,
            ActivityImageSyncStatus.deleted,
          ]),
        );
        expect(
          localDataSource.images[1]!.status,
          ActivityImageSyncStatus.deleted,
        );
        expect(localDataSource.images[1]!.remoteImageId, remoteImageId);
        expect(remoteDataSource.deleteRemoteImageCount, 1);
      },
    );

    test(
      'remote delete failure stays deleteQueued instead of upload retrying',
      () async {
        remoteDataSource.deleteRemoteImageError = Exception('s3 timeout');
        localDataSource.addImage(
          _image(
            localId: 1,
            localWorkoutId: localWorkoutId,
            remoteActivityId: remoteActivityId,
            remoteImageId: remoteImageId,
            clientImageId: clientImageId,
            localPath: appPrivatePath,
            thumbnailPath: thumbnailPath,
            status: ActivityImageSyncStatus.deleteQueued,
          ),
        );

        await repository.syncPendingImages();

        expect(
          localDataSource.images[1]!.status,
          ActivityImageSyncStatus.deleteQueued,
        );
        expect(localDataSource.images[1]!.retryCount, 1);
        expect(localDataSource.images[1]!.lastError, contains('s3 timeout'));
        expect(remoteDataSource.requestUploadUrlCount, 0);
      },
    );

    test('missing local file is a permanent failed state', () async {
      fileService.existingPaths.clear();
      localDataSource.addImage(
        _image(
          localId: 1,
          localWorkoutId: localWorkoutId,
          clientImageId: clientImageId,
          localPath: appPrivatePath,
          thumbnailPath: thumbnailPath,
          status: ActivityImageSyncStatus.queued,
        ),
      );

      await repository.syncPendingImages();

      expect(
        localDataSource.statusEvents,
        isNot(contains(ActivityImageSyncStatus.uploading)),
      );
      expect(
        localDataSource.statusEvents,
        contains(ActivityImageSyncStatus.failed),
      );
      expect(localDataSource.images[1]!.status, ActivityImageSyncStatus.failed);
      expect(
        localDataSource.images[1]!.lastError,
        contains('missing_local_file'),
      );
    });

    test(
      'stale uploading images reset to queued before sync selection',
      () async {
        authLocalDataSource.authHeaders = null;
        localDataSource.addImage(
          _image(
            localId: 1,
            localWorkoutId: localWorkoutId,
            clientImageId: clientImageId,
            localPath: appPrivatePath,
            thumbnailPath: thumbnailPath,
            status: ActivityImageSyncStatus.uploading,
            updatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
          ),
        );

        await repository.syncPendingImages();

        expect(localDataSource.resetStaleUploadingCalled, isTrue);
        expect(
          localDataSource.images[1]!.status,
          ActivityImageSyncStatus.queued,
        );
      },
    );

    test(
      'waitingForActivitySync is used without a remote activity ID',
      () async {
        workoutLocalDataSource.workouts[localWorkoutId] = _workout(
          localWorkoutId: localWorkoutId,
          remoteActivityId: null,
          userId: userId,
        );
        localDataSource.addImage(
          _image(
            localId: 1,
            localWorkoutId: localWorkoutId,
            clientImageId: clientImageId,
            localPath: appPrivatePath,
            thumbnailPath: thumbnailPath,
            status: ActivityImageSyncStatus.queued,
          ),
        );

        await repository.syncPendingImages();

        expect(
          localDataSource.images[1]!.status,
          ActivityImageSyncStatus.waitingForActivitySync,
        );
        expect(remoteDataSource.requestUploadUrlCount, 0);
      },
    );

    test('delete local-only image marks deleted and removes files', () async {
      localDataSource.addImage(
        _image(
          localId: 1,
          localWorkoutId: localWorkoutId,
          clientImageId: clientImageId,
          localPath: appPrivatePath,
          thumbnailPath: thumbnailPath,
          status: ActivityImageSyncStatus.queued,
        ),
      );

      await repository.deleteImage(1);

      expect(
        localDataSource.images[1]!.status,
        ActivityImageSyncStatus.deleted,
      );
      expect(
        fileService.deletedPaths,
        containsAll([appPrivatePath, thumbnailPath]),
      );
    });

    test('delete uploaded image marks deleteQueued for remote sync', () async {
      authLocalDataSource.authHeaders = null;
      localDataSource.addImage(
        _image(
          localId: 1,
          localWorkoutId: localWorkoutId,
          remoteActivityId: remoteActivityId,
          remoteImageId: remoteImageId,
          clientImageId: clientImageId,
          localPath: appPrivatePath,
          thumbnailPath: thumbnailPath,
          status: ActivityImageSyncStatus.uploaded,
        ),
      );

      await repository.deleteImage(1);
      await _pumpMicrotasks();

      expect(
        localDataSource.images[1]!.status,
        ActivityImageSyncStatus.deleteQueued,
      );
      expect(fileService.deletedPaths, isEmpty);
      expect(remoteDataSource.deleteRemoteImageCount, 0);
    });
  });
}

Future<void> _pumpMicrotasks([int times = 20]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

WorkoutSessionEntity _workout({
  required int localWorkoutId,
  required int? remoteActivityId,
  required int userId,
}) {
  return WorkoutSessionEntity(
    id: '$localWorkoutId',
    clientSyncId: 'rr-test-$localWorkoutId',
    remoteActivityId: remoteActivityId,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: DateTime(2026, 6, 9, 7),
    endTime: DateTime(2026, 6, 9, 8),
    userId: userId,
  );
}

ActivityImageEntity _image({
  required int localId,
  required int localWorkoutId,
  int? remoteActivityId,
  int? remoteImageId,
  required String clientImageId,
  required String localPath,
  String? thumbnailPath,
  required ActivityImageSyncStatus status,
  DateTime? updatedAt,
}) {
  final now = DateTime(2026, 6, 9, 8);
  return ActivityImageEntity(
    localId: localId,
    localWorkoutId: localWorkoutId,
    remoteActivityId: remoteActivityId,
    remoteImageId: remoteImageId,
    clientImageId: clientImageId,
    localPath: localPath,
    thumbnailPath: thumbnailPath,
    remoteUrl:
        remoteImageId == null ? null : 'https://cdn.example.com/$localId',
    remoteUrlExpiresAt: remoteImageId == null ? null : DateTime(2026, 6, 9, 9),
    s3Key:
        remoteImageId == null
            ? null
            : 'activity-images/1/900/$clientImageId.jpg',
    contentType: 'image/jpeg',
    sizeBytes: 1024,
    checksumSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    width: 800,
    height: 600,
    status: status,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

ActivityImageEntity _copyImage(
  ActivityImageEntity image, {
  int? localId,
  int? remoteActivityId,
  int? remoteImageId,
  String? remoteUrl,
  DateTime? remoteUrlExpiresAt,
  String? s3Key,
  ActivityImageSyncStatus? status,
  int? retryCount,
  String? lastError,
  DateTime? nextRetryAt,
  DateTime? updatedAt,
}) {
  return ActivityImageEntity(
    localId: localId ?? image.localId,
    localWorkoutId: image.localWorkoutId,
    remoteActivityId: remoteActivityId ?? image.remoteActivityId,
    remoteImageId: remoteImageId ?? image.remoteImageId,
    clientImageId: image.clientImageId,
    localPath: image.localPath,
    thumbnailPath: image.thumbnailPath,
    remoteUrl: remoteUrl ?? image.remoteUrl,
    remoteUrlExpiresAt: remoteUrlExpiresAt ?? image.remoteUrlExpiresAt,
    s3Key: s3Key ?? image.s3Key,
    contentType: image.contentType,
    sizeBytes: image.sizeBytes,
    checksumSha256: image.checksumSha256,
    width: image.width,
    height: image.height,
    sortOrder: image.sortOrder,
    caption: image.caption,
    status: status ?? image.status,
    retryCount: retryCount ?? image.retryCount,
    lastError: lastError ?? image.lastError,
    nextRetryAt: nextRetryAt ?? image.nextRetryAt,
    createdAt: image.createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );
}

class FakeActivityImageLocalDataSource implements ActivityImageLocalDataSource {
  final List<String> events;
  final Map<int, ActivityImageEntity> images = <int, ActivityImageEntity>{};
  final List<ActivityImageEntity> insertedImages = <ActivityImageEntity>[];
  final List<ActivityImageSyncStatus> statusEvents =
      <ActivityImageSyncStatus>[];

  int _nextId = 1;
  bool resetStaleUploadingCalled = false;
  bool readyImagesEnabled = true;

  FakeActivityImageLocalDataSource(this.events);

  void addImage(ActivityImageEntity image) {
    images[image.localId!] = image;
    if (image.localId! >= _nextId) {
      _nextId = image.localId! + 1;
    }
  }

  @override
  Future<int> insertWorkoutImage(ActivityImageEntity image) async {
    final localId = _nextId++;
    final saved = _copyImage(image, localId: localId);
    images[localId] = saved;
    insertedImages.add(image);
    events.add('insert');
    return localId;
  }

  @override
  Future<List<ActivityImageEntity>> getWorkoutImages(int workoutId) async {
    return images.values
        .where(
          (image) =>
              image.localWorkoutId == workoutId &&
              image.status != ActivityImageSyncStatus.deleted,
        )
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<ActivityImageEntity?> getWorkoutImage(int localImageId) async {
    return images[localImageId];
  }

  @override
  Future<List<ActivityImageEntity>> getImagesReadyForSync(
    int userId,
    DateTime now,
  ) async {
    if (!readyImagesEnabled) {
      return <ActivityImageEntity>[];
    }

    return images.values.where((image) {
      final statusReady =
          image.status == ActivityImageSyncStatus.queued ||
          image.status == ActivityImageSyncStatus.waitingForActivitySync ||
          image.status == ActivityImageSyncStatus.retrying ||
          image.status == ActivityImageSyncStatus.deleteQueued;
      final retryReady =
          image.nextRetryAt == null || !image.nextRetryAt!.isAfter(now);
      return statusReady && retryReady;
    }).toList();
  }

  @override
  Future<List<ActivityImageEntity>> getActiveImagesForJanitor(
    int userId,
  ) async {
    return images.values.where((image) {
      return image.status == ActivityImageSyncStatus.queued ||
          image.status == ActivityImageSyncStatus.waitingForActivitySync ||
          image.status == ActivityImageSyncStatus.uploading ||
          image.status == ActivityImageSyncStatus.retrying ||
          image.status == ActivityImageSyncStatus.deleteQueued ||
          image.status == ActivityImageSyncStatus.deleting ||
          image.status == ActivityImageSyncStatus.replaceQueued;
    }).toList();
  }

  @override
  Future<bool> markImageUploadingIfReady(int localImageId) async {
    final image = images[localImageId]!;
    final ready =
        image.status == ActivityImageSyncStatus.queued ||
        image.status == ActivityImageSyncStatus.waitingForActivitySync ||
        image.status == ActivityImageSyncStatus.retrying;
    if (!ready) {
      return false;
    }
    _setStatus(localImageId, ActivityImageSyncStatus.uploading);
    return true;
  }

  @override
  Future<bool> markImageWaitingForActivitySyncIfReady(int localImageId) async {
    final image = images[localImageId]!;
    final ready =
        image.status == ActivityImageSyncStatus.queued ||
        image.status == ActivityImageSyncStatus.waitingForActivitySync ||
        image.status == ActivityImageSyncStatus.retrying;
    if (!ready) {
      return false;
    }
    _setStatus(localImageId, ActivityImageSyncStatus.waitingForActivitySync);
    return true;
  }

  @override
  Future<ActivityImageSyncStatus?> recordImageUploadResult({
    required int localImageId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) async {
    final image = images[localImageId]!;
    final finalStatus =
        image.status == ActivityImageSyncStatus.deleteQueued ||
                image.status == ActivityImageSyncStatus.deleting ||
                image.status == ActivityImageSyncStatus.deleted ||
                image.status == ActivityImageSyncStatus.replaceQueued
            ? ActivityImageSyncStatus.deleteQueued
            : ActivityImageSyncStatus.uploaded;
    images[localImageId] = _copyImage(
      image,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
      s3Key: s3Key,
      status: finalStatus,
      retryCount: 0,
    );
    statusEvents.add(finalStatus);
    events.add(finalStatus.name);
    return finalStatus;
  }

  @override
  Future<void> markImageRetrying({
    required int localImageId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) async {
    final image = images[localImageId]!;
    images[localImageId] = _copyImage(
      image,
      status: ActivityImageSyncStatus.retrying,
      retryCount: retryCount,
      lastError: error,
      nextRetryAt: nextRetryAt,
    );
    statusEvents.add(ActivityImageSyncStatus.retrying);
  }

  @override
  Future<void> markImageFailed({
    required int localImageId,
    required String error,
  }) async {
    final image = images[localImageId]!;
    images[localImageId] = _copyImage(
      image,
      status: ActivityImageSyncStatus.failed,
      lastError: error,
    );
    statusEvents.add(ActivityImageSyncStatus.failed);
  }

  @override
  Future<void> markImageDeleteQueuedRetrying({
    required int localImageId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) async {
    final image = images[localImageId]!;
    images[localImageId] = _copyImage(
      image,
      status: ActivityImageSyncStatus.deleteQueued,
      retryCount: retryCount,
      lastError: error,
      nextRetryAt: nextRetryAt,
    );
    statusEvents.add(ActivityImageSyncStatus.deleteQueued);
  }

  @override
  Future<void> markImageDeleteQueued(int localImageId) async {
    _setStatus(localImageId, ActivityImageSyncStatus.deleteQueued);
  }

  @override
  Future<void> markImageReplaceQueued(int localImageId) async {
    _setStatus(localImageId, ActivityImageSyncStatus.replaceQueued);
  }

  @override
  Future<void> markReplaceQueuedImagesDeleteQueued(int workoutId) async {
    for (final entry in images.entries.toList()) {
      final image = entry.value;
      if (image.localWorkoutId == workoutId &&
          image.status == ActivityImageSyncStatus.replaceQueued) {
        images[entry.key] = _copyImage(
          image,
          status: ActivityImageSyncStatus.deleteQueued,
        );
        statusEvents.add(ActivityImageSyncStatus.deleteQueued);
      }
    }
  }

  @override
  Future<void> markImageDeleting(int localImageId) async {
    _setStatus(localImageId, ActivityImageSyncStatus.deleting);
  }

  @override
  Future<void> markImageDeleted(int localImageId) async {
    _setStatus(localImageId, ActivityImageSyncStatus.deleted);
  }

  @override
  Future<void> resetStaleUploadingImages(DateTime staleBefore) async {
    resetStaleUploadingCalled = true;
    for (final entry in images.entries.toList()) {
      final image = entry.value;
      if (!image.updatedAt.isBefore(staleBefore)) {
        continue;
      }
      if (image.status == ActivityImageSyncStatus.uploading) {
        images[entry.key] = _copyImage(
          image,
          status: ActivityImageSyncStatus.queued,
        );
      } else if (image.status == ActivityImageSyncStatus.deleting) {
        images[entry.key] = _copyImage(
          image,
          status: ActivityImageSyncStatus.deleteQueued,
        );
      }
    }
  }

  @override
  Future<void> updateRemoteImageUrl({
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
  }) async {
    final entry = images.entries.firstWhere(
      (entry) => entry.value.remoteImageId == remoteImageId,
    );
    images[entry.key] = _copyImage(
      entry.value,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
    );
  }

  @override
  Future<void> updateRemoteImageMetadata({
    required int localImageId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) async {
    final image = images[localImageId]!;
    images[localImageId] = _copyImage(
      image,
      remoteActivityId: remoteActivityId,
      remoteImageId: remoteImageId,
      remoteUrl: remoteUrl,
      remoteUrlExpiresAt: remoteUrlExpiresAt,
      s3Key: s3Key,
    );
  }

  void _setStatus(int localImageId, ActivityImageSyncStatus status) {
    images[localImageId] = _copyImage(images[localImageId]!, status: status);
    statusEvents.add(status);
    events.add(status.name);
  }
}

class FakeActivityImageRemoteDataSource
    implements ActivityImageRemoteDataSource {
  final List<String> events;

  Object? requestUploadUrlError;
  Object? uploadError;
  Object? confirmUploadError;
  Object? deleteRemoteImageError;
  Future<void> Function()? beforeConfirm;
  int requestUploadUrlCount = 0;
  int deleteRemoteImageCount = 0;

  FakeActivityImageRemoteDataSource(this.events);

  @override
  Future<ActivityImageUploadIntent> requestUploadUrl({
    required int remoteActivityId,
    required ActivityImageEntity image,
    required Map<String, String> authHeaders,
  }) async {
    requestUploadUrlCount++;
    events.add('request-url');
    final error = requestUploadUrlError;
    if (error != null) {
      throw error;
    }

    return ActivityImageUploadIntent(
      imageId: 700,
      clientImageId: image.clientImageId,
      key: 'activity-images/1/$remoteActivityId/${image.clientImageId}.jpg',
      uploadUrl: 'https://upload.example.com/${image.clientImageId}',
    );
  }

  @override
  Future<void> uploadToS3({
    required String uploadUrl,
    required String localPath,
    required String contentType,
  }) async {
    events.add('upload-s3');
    final error = uploadError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<RemoteActivityImage> confirmUpload({
    required int remoteActivityId,
    required ActivityImageEntity image,
    required String key,
    required Map<String, String> authHeaders,
  }) async {
    final callback = beforeConfirm;
    if (callback != null) {
      await callback();
    }

    events.add('confirm');
    final error = confirmUploadError;
    if (error != null) {
      throw error;
    }

    return RemoteActivityImage(
      id: 700,
      clientImageId: image.clientImageId,
      key: key,
      url: 'https://signed.example.com/$key',
      urlExpiresAt: DateTime(2026, 6, 9, 9),
      contentType: image.contentType,
      sizeBytes: image.sizeBytes,
    );
  }

  @override
  Future<List<RemoteActivityImage>> fetchImages({
    required int remoteActivityId,
    required Map<String, String> authHeaders,
  }) async {
    return <RemoteActivityImage>[];
  }

  @override
  Future<void> deleteRemoteImage({
    required int remoteActivityId,
    required int remoteImageId,
    required Map<String, String> authHeaders,
  }) async {
    deleteRemoteImageCount++;
    events.add('delete-remote');
    final error = deleteRemoteImageError;
    if (error != null) {
      throw error;
    }
  }
}

class FakeActivityImageFileService implements ActivityImageFileService {
  final List<String> events;
  final Set<String> existingPaths = <String>{};
  final List<String> deletedPaths = <String>[];
  late PreparedActivityImage preparedImage;

  FakeActivityImageFileService(this.events);

  @override
  Future<PreparedActivityImage> prepareImage({
    required int userId,
    required int localWorkoutId,
    required XFile pickedFile,
  }) async {
    events.add('prepare');
    return preparedImage;
  }

  @override
  Future<bool> exists(String path) async => existingPaths.contains(path);

  @override
  Future<List<int>> readBytes(String path) async => <int>[1, 2, 3];

  @override
  Future<void> deleteIfExists(String? path) async {
    if (path != null) {
      deletedPaths.add(path);
    }
  }
}

class FakeAuthLocalDataSource extends AuthLocalDataSource {
  Map<String, String>? authHeaders = const {'Authorization': 'Bearer test'};

  @override
  Future<Map<String, String>?> getAuthHeaders() async => authHeaders;
}

class FakeWorkoutLocalDataSource implements WorkoutLocalDataSource {
  final Map<int, WorkoutSessionEntity> workouts = <int, WorkoutSessionEntity>{};

  @override
  Future<WorkoutSessionEntity?> getWorkoutFromLocalDatabase(
    int workoutId,
  ) async {
    return workouts[workoutId];
  }

  @override
  Future<int> saveWorkoutInLocalDatabase(WorkoutSessionEntity workout) async {
    throw UnimplementedError();
  }

  @override
  Future<List<WorkoutSessionEntity>> getWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteWorkoutFromLocalDatabase(int workoutId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> markWorkoutAsSyncedInLocalDatabase(int workoutId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updateRemoteActivityId(int localId, int remoteId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<WorkoutDeleteQueueEntry>> getWorkoutDeletesReadyForSync(
    int userId,
    DateTime now,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> markWorkoutDeleteDeleting(int queueId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> markWorkoutDeleteRetrying({
    required int queueId,
    required int retryCount,
    required String error,
    required DateTime nextRetryAt,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> completeWorkoutDelete({
    required int queueId,
    required int localWorkoutId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> resetStaleWorkoutDeletes(DateTime staleBefore) async {
    throw UnimplementedError();
  }

  @override
  Future<void> ensureClientSyncIds() async {
    throw UnimplementedError();
  }

  @override
  Future<void> clearAllDataFromLocalDatabase() async {
    throw UnimplementedError();
  }

  @override
  Future<WorkoutStatistics> getWorkoutStatistics(
    int userId, {
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, WorkoutStatistics>> getWorkoutStatisticsByType(
    int userId,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PaginatedWorkouts> getPaginatedWorkouts(
    int userId, {
    int page = 1,
    int limit = 20,
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    bool loadTrackingPoints = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<int> getWorkoutCount(int userId) async {
    throw UnimplementedError();
  }
}

class FakeAuthRepository implements AuthRepository {
  UserEntity? currentUser;

  FakeAuthRepository({required this.currentUser});

  @override
  Future<UserEntity?> getCurrentUser() async => currentUser;

  @override
  Future<UserEntity> refreshToken() async => currentUser!;

  @override
  Future<UserEntity> login(LoginRequestEntity request) async {
    throw UnimplementedError();
  }

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) async {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {
    throw UnimplementedError();
  }

  @override
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> needsTokenRefresh() async {
    throw UnimplementedError();
  }

  @override
  Future<SessionValidationStatus> validateSession() async {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasOfflineAccess() async {
    throw UnimplementedError();
  }

  @override
  Future<void> clearAuthData() async {
    throw UnimplementedError();
  }

  @override
  Future<void> markAuthCleanupPending() async {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasPendingAuthCleanup() async {
    throw UnimplementedError();
  }

  @override
  Future<bool> canStayLoggedInOffline() async {
    throw UnimplementedError();
  }

  @override
  Future<bool> needsBackendSync() async {
    throw UnimplementedError();
  }

  @override
  Future<void> updateLastBackendSync() async {
    throw UnimplementedError();
  }

  @override
  Future<void> printStoredData() async {
    throw UnimplementedError();
  }
}
