import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/local_db_test_harness.dart';

void main() {
  setUpAll(LocalDbTestHarness.initializeFfi);

  late LocalDbTestHarness harness;

  setUp(() async {
    harness = await LocalDbTestHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('owner-scoped workout access', () {
    test(
      'a foreign owner cannot read, mutate, or delete a known workout ID',
      () async {
        final service = await harness.openService();
        final database = await service.database;
        final workoutId = await service.saveWorkoutInLocalDatabase(
          _workout(userId: 7, clientSyncId: 'owner-workout'),
          userId: 7,
        );

        expect(
          await service.getWorkoutFromLocalDatabase(workoutId, userId: 8),
          isNull,
        );
        await service.markWorkoutAsSyncedInLocalDatabase(workoutId, userId: 8);
        await service.updateRemoteActivityId(workoutId, 8001, userId: 8);
        expect(
          await service.recordWorkoutSyncSuccess(
            userId: 8,
            localWorkoutId: workoutId,
            clientSyncId: 'owner-workout',
            remoteActivityId: 8002,
          ),
          isFalse,
        );
        await service.deleteWorkoutFromLocalDatabase(workoutId, userId: 8);

        final unchanged = await _workoutRow(database, workoutId);
        expect(unchanged['user_id'], 7);
        expect(unchanged['synced'], 0);
        expect(unchanged['remote_activity_id'], isNull);
        expect(unchanged['deleted_locally'], 0);

        expect(
          await service.recordWorkoutSyncSuccess(
            userId: 7,
            localWorkoutId: workoutId,
            clientSyncId: 'wrong-client-id',
            remoteActivityId: 7001,
          ),
          isFalse,
        );
        expect(
          await service.recordWorkoutSyncSuccess(
            userId: 7,
            localWorkoutId: workoutId,
            clientSyncId: 'owner-workout',
            remoteActivityId: 7001,
          ),
          isTrue,
        );
        final ownedUpdate = await _workoutRow(database, workoutId);
        expect(ownedUpdate['synced'], 1);
        expect(ownedUpdate['remote_activity_id'], 7001);
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test(
      'client-ID repair and user purge affect only the requested owner',
      () async {
        final service = await harness.openService();
        final database = await service.database;
        final ownerId = await service.saveWorkoutInLocalDatabase(
          _workout(userId: 7, clientSyncId: 'owner-before-repair'),
          userId: 7,
        );
        final otherId = await service.saveWorkoutInLocalDatabase(
          _workout(userId: 8, clientSyncId: 'other-before-repair'),
          userId: 8,
        );
        await database.update(
          'workouts',
          <String, Object?>{'client_sync_id': ''},
          where: 'id IN (?, ?)',
          whereArgs: <Object?>[ownerId, otherId],
        );

        await service.ensureClientSyncIds(7);

        expect(
          ((await _workoutRow(database, ownerId))['client_sync_id'] as String),
          isNotEmpty,
        );
        expect((await _workoutRow(database, otherId))['client_sync_id'], '');

        await service.clearUserDataFromLocalDatabase(7);
        expect(await _workoutExists(database, ownerId), isFalse);
        expect(await _workoutExists(database, otherId), isTrue);
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  });

  group('owner-scoped activity images', () {
    test('a foreign owner cannot attach, read, or mutate image rows', () async {
      final service = await harness.openService();
      final database = await service.database;
      final workoutId = await service.saveWorkoutInLocalDatabase(
        _workout(userId: 7, clientSyncId: 'image-owner'),
        userId: 7,
      );
      final queuedId = await service.insertWorkoutImage(
        _image(workoutId, 'queued'),
        userId: 7,
      );
      final deleteQueuedId = await service.insertWorkoutImage(
        _image(workoutId, 'delete-queued'),
        userId: 7,
      );
      final refreshableId = await service.insertWorkoutImage(
        _image(workoutId, 'refreshable'),
        userId: 7,
      );
      final replaceQueuedId = await service.insertWorkoutImage(
        _image(workoutId, 'replace-queued'),
        userId: 7,
      );
      await database.update(
        'workout_images',
        <String, Object?>{'status': 'deleteQueued'},
        where: 'id = ?',
        whereArgs: <Object?>[deleteQueuedId],
      );
      await database.update(
        'workout_images',
        <String, Object?>{'status': 'failed', 'remote_image_id': 9001},
        where: 'id = ?',
        whereArgs: <Object?>[refreshableId],
      );
      await database.update(
        'workout_images',
        <String, Object?>{'status': 'replaceQueued'},
        where: 'id = ?',
        whereArgs: <Object?>[replaceQueuedId],
      );
      final before = await _imageRows(database);

      await expectLater(
        service.insertWorkoutImage(
          _image(workoutId, 'foreign-insert'),
          userId: 8,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await service.getWorkoutImages(workoutId, userId: 8), isEmpty);
      expect(await service.getWorkoutImage(queuedId, userId: 8), isNull);
      expect(
        await service.markImageUploadingIfReady(queuedId, userId: 8),
        isFalse,
      );
      expect(
        await service.markImageWaitingForActivitySyncIfReady(
          queuedId,
          userId: 8,
        ),
        isFalse,
      );
      expect(
        await service.recordImageUploadResult(
          localImageId: queuedId,
          userId: 8,
          remoteActivityId: 8001,
          remoteImageId: 8002,
          remoteUrl: 'https://example.invalid/foreign',
          remoteUrlExpiresAt: null,
          s3Key: 'foreign-key',
        ),
        isNull,
      );
      await service.markImageRetrying(
        localImageId: queuedId,
        userId: 8,
        error: 'foreign',
        nextRetryAt: DateTime.utc(2026, 7, 12),
        retryCount: 9,
      );
      await service.markImageDeleteQueuedRetrying(
        localImageId: queuedId,
        userId: 8,
        error: 'foreign',
        nextRetryAt: DateTime.utc(2026, 7, 12),
        retryCount: 9,
      );
      await service.markImageFailed(
        localImageId: queuedId,
        userId: 8,
        error: 'foreign',
      );
      await service.markImageDeleteQueued(queuedId, userId: 8);
      await service.markImageReplaceQueued(queuedId, userId: 8);
      expect(
        await service.markImageDeleting(deleteQueuedId, userId: 8),
        isFalse,
      );
      await service.markImageDeleted(queuedId, userId: 8);
      await service.markReplaceQueuedImagesDeleteQueued(workoutId, userId: 8);
      await service.updateRemoteImageUrl(
        userId: 8,
        remoteImageId: 9001,
        remoteUrl: 'https://example.invalid/foreign',
        remoteUrlExpiresAt: null,
      );
      await service.updateRemoteImageMetadata(
        localImageId: refreshableId,
        userId: 8,
        remoteActivityId: 8001,
        remoteImageId: 8002,
        remoteUrl: 'https://example.invalid/foreign',
        remoteUrlExpiresAt: null,
        s3Key: 'foreign-key',
      );

      expect(await _imageRows(database), before);
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  group('owned delete queue and maintenance', () {
    test('queue completion validates owner and queue-workout tuple', () async {
      final service = await harness.openService();
      final database = await service.database;
      final ownerWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(
          userId: 7,
          clientSyncId: 'delete-owner',
          remoteActivityId: 7001,
        ),
        userId: 7,
      );
      final otherOwnerWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(
          userId: 8,
          clientSyncId: 'delete-other-owner',
          remoteActivityId: 8001,
        ),
        userId: 8,
      );
      final secondOwnerWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(
          userId: 7,
          clientSyncId: 'delete-owner-second',
          remoteActivityId: 7002,
        ),
        userId: 7,
      );
      await service.deleteWorkoutFromLocalDatabase(ownerWorkoutId, userId: 7);
      final queue =
          (await service.getWorkoutDeletesReadyForSync(
            7,
            DateTime.utc(2026, 7, 12),
          )).single;

      expect(
        await service.markWorkoutDeleteDeleting(queue.id, userId: 8),
        isFalse,
      );
      await service.markWorkoutDeleteRetrying(
        queueId: queue.id,
        userId: 8,
        retryCount: 5,
        error: 'foreign',
        nextRetryAt: DateTime.utc(2026, 7, 13),
      );
      await service.completeWorkoutDelete(
        queueId: queue.id,
        localWorkoutId: ownerWorkoutId,
        userId: 8,
      );
      await service.completeWorkoutDelete(
        queueId: queue.id,
        localWorkoutId: secondOwnerWorkoutId,
        userId: 7,
      );

      expect(await _workoutExists(database, ownerWorkoutId), isTrue);
      expect(await _workoutExists(database, otherOwnerWorkoutId), isTrue);
      expect(await _workoutExists(database, secondOwnerWorkoutId), isTrue);
      final unchangedQueue = await _queueRow(database, queue.id);
      expect(unchangedQueue['status'], 'queued');
      expect(unchangedQueue['retry_count'], 0);

      expect(
        await service.markWorkoutDeleteDeleting(queue.id, userId: 7),
        isTrue,
      );
      await service.completeWorkoutDelete(
        queueId: queue.id,
        localWorkoutId: ownerWorkoutId,
        userId: 7,
      );
      expect(await _workoutExists(database, ownerWorkoutId), isFalse);
      expect(await _workoutExists(database, otherOwnerWorkoutId), isTrue);
      expect(await _workoutExists(database, secondOwnerWorkoutId), isTrue);
      expect(
        await _countWhere(database, 'workout_delete_queue', 'id = ?', <Object?>[
          queue.id,
        ]),
        0,
      );
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test('stale queue and image resets affect only one owner', () async {
      final service = await harness.openService();
      final database = await service.database;
      final ownerWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(
          userId: 7,
          clientSyncId: 'stale-owner',
          remoteActivityId: 7001,
        ),
        userId: 7,
      );
      final otherWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(
          userId: 8,
          clientSyncId: 'stale-other',
          remoteActivityId: 8001,
        ),
        userId: 8,
      );
      final ownerUploadingId = await service.insertWorkoutImage(
        _image(ownerWorkoutId, 'owner-uploading'),
        userId: 7,
      );
      final ownerDeletingId = await service.insertWorkoutImage(
        _image(ownerWorkoutId, 'owner-deleting'),
        userId: 7,
      );
      final otherUploadingId = await service.insertWorkoutImage(
        _image(otherWorkoutId, 'other-uploading'),
        userId: 8,
      );
      final old = DateTime.utc(2026, 7, 10).toIso8601String();
      await database.rawUpdate(
        '''
        UPDATE workout_images
        SET status = CASE WHEN id = ? THEN 'deleting' ELSE 'uploading' END,
            updated_at = ?
        WHERE id IN (?, ?, ?)
        ''',
        <Object?>[
          ownerDeletingId,
          old,
          ownerUploadingId,
          ownerDeletingId,
          otherUploadingId,
        ],
      );

      await service.deleteWorkoutFromLocalDatabase(ownerWorkoutId, userId: 7);
      await service.deleteWorkoutFromLocalDatabase(otherWorkoutId, userId: 8);
      final ownerQueue =
          (await service.getWorkoutDeletesReadyForSync(
            7,
            DateTime.utc(2026, 7, 12),
          )).single;
      final otherQueue =
          (await service.getWorkoutDeletesReadyForSync(
            8,
            DateTime.utc(2026, 7, 12),
          )).single;
      await database.update(
        'workout_delete_queue',
        <String, Object?>{'status': 'deleting', 'updated_at': old},
        where: 'id IN (?, ?)',
        whereArgs: <Object?>[ownerQueue.id, otherQueue.id],
      );

      final cutoff = DateTime.utc(2026, 7, 11);
      await service.resetStaleWorkoutDeletes(7, cutoff);
      await service.resetStaleUploadingImages(7, cutoff);

      expect((await _queueRow(database, ownerQueue.id))['status'], 'queued');
      expect((await _queueRow(database, otherQueue.id))['status'], 'deleting');
      expect((await _imageRow(database, ownerUploadingId))['status'], 'queued');
      expect(
        (await _imageRow(database, ownerDeletingId))['status'],
        'deleteQueued',
      );
      expect(
        (await _imageRow(database, otherUploadingId))['status'],
        'uploading',
      );
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });
}

WorkoutSessionEntity _workout({
  required int userId,
  required String clientSyncId,
  int? remoteActivityId,
}) {
  return WorkoutSessionEntity(
    clientSyncId: clientSyncId,
    remoteActivityId: remoteActivityId,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: DateTime.utc(2026, 7, 11, 10),
    endTime: DateTime.utc(2026, 7, 11, 11),
    totalDistance: 1000,
    averageSpeed: 1000 / 3600,
    userId: userId,
  );
}

ActivityImageEntity _image(int workoutId, String clientImageId) {
  final now = DateTime.utc(2026, 7, 11, 11);
  return ActivityImageEntity(
    localWorkoutId: workoutId,
    clientImageId: clientImageId,
    localPath: '/test/$clientImageId.jpg',
    contentType: 'image/jpeg',
    sizeBytes: 10,
    status: ActivityImageSyncStatus.queued,
    createdAt: now,
    updatedAt: now,
  );
}

Future<Map<String, Object?>> _workoutRow(Database database, int id) async {
  return (await database.query(
    'workouts',
    where: 'id = ?',
    whereArgs: <Object?>[id],
  )).single;
}

Future<Map<String, Object?>> _imageRow(Database database, int id) async {
  return (await database.query(
    'workout_images',
    where: 'id = ?',
    whereArgs: <Object?>[id],
  )).single;
}

Future<List<Map<String, Object?>>> _imageRows(Database database) {
  return database.query('workout_images', orderBy: 'id ASC');
}

Future<Map<String, Object?>> _queueRow(Database database, int id) async {
  return (await database.query(
    'workout_delete_queue',
    where: 'id = ?',
    whereArgs: <Object?>[id],
  )).single;
}

Future<bool> _workoutExists(Database database, int id) async {
  return await _countWhere(database, 'workouts', 'id = ?', <Object?>[id]) == 1;
}

Future<int> _countWhere(
  Database database,
  String table,
  String where,
  List<Object?> args,
) async {
  final rows = await database.rawQuery(
    'SELECT COUNT(*) AS count FROM $table WHERE $where',
    args,
  );
  return (rows.single['count'] as num).toInt();
}
