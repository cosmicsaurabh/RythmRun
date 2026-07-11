import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
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

  group('fresh version 6 schema', () {
    test(
      'enables foreign keys and creates the exact required indexes',
      () async {
        final service = await harness.openService();
        final database = await service.database;

        expect(await database.getVersion(), 6);
        expect(await _pragmaInt(database, 'foreign_keys'), 1);
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        await _expectIndex(
          database,
          table: 'workouts',
          name: 'idx_workouts_user_start_time',
          columns: const <({String name, bool descending})>[
            (name: 'user_id', descending: false),
            (name: 'start_time', descending: true),
          ],
        );
        await _expectIndex(
          database,
          table: 'workouts',
          name: 'idx_workouts_user_client_sync_id',
          columns: const <({String name, bool descending})>[
            (name: 'user_id', descending: false),
            (name: 'client_sync_id', descending: false),
          ],
          unique: true,
        );
        await _expectIndex(
          database,
          table: 'tracking_points',
          name: 'idx_tracking_points_workout_timestamp',
          columns: const <({String name, bool descending})>[
            (name: 'workout_id', descending: false),
            (name: 'timestamp', descending: false),
          ],
        );
        await _expectIndex(
          database,
          table: 'status_changes',
          name: 'idx_status_changes_workout_timestamp',
          columns: const <({String name, bool descending})>[
            (name: 'workout_id', descending: false),
            (name: 'timestamp', descending: false),
          ],
        );
        await _expectIndex(
          database,
          table: 'workout_delete_queue',
          name: 'idx_workout_delete_queue_user_status',
          columns: const <({String name, bool descending})>[
            (name: 'user_id', descending: false),
            (name: 'status', descending: false),
            (name: 'next_retry_at', descending: false),
          ],
        );
        await _expectIndex(
          database,
          table: 'workout_images',
          name: 'idx_workout_images_workout_id',
          columns: const <({String name, bool descending})>[
            (name: 'workout_id', descending: false),
          ],
        );
        await _expectIndex(
          database,
          table: 'workout_images',
          name: 'idx_workout_images_status_next_retry',
          columns: const <({String name, bool descending})>[
            (name: 'status', descending: false),
            (name: 'next_retry_at', descending: false),
          ],
        );
        await _expectIndex(
          database,
          table: 'workout_images',
          name: 'idx_workout_images_remote_activity_id',
          columns: const <({String name, bool descending})>[
            (name: 'remote_activity_id', descending: false),
          ],
        );

        for (final table in <String>[
          'tracking_points',
          'status_changes',
          'workout_images',
        ]) {
          final foreignKeys = await database.rawQuery(
            'PRAGMA foreign_key_list("$table")',
          );
          expect(foreignKeys, hasLength(1), reason: table);
          expect(foreignKeys.single['table'], 'workouts', reason: table);
          expect(foreignKeys.single['from'], 'workout_id', reason: table);
          expect(foreignKeys.single['to'], 'id', reason: table);
          expect(foreignKeys.single['on_delete'], 'CASCADE', reason: table);
        }
      },
    );

    test(
      'enables foreign keys again after the connection is reopened',
      () async {
        final firstService = await harness.openService();
        final firstDatabase = await firstService.database;
        expect(await _pragmaInt(firstDatabase, 'foreign_keys'), 1);

        await firstService.close();

        final reopenedService = await harness.openService();
        final reopenedDatabase = await reopenedService.database;
        expect(await _pragmaInt(reopenedDatabase, 'foreign_keys'), 1);
        expect(
          await reopenedDatabase.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      },
    );

    test(
      'enforces composite uniqueness and idempotent local save identity',
      () async {
        final service = await harness.openService();
        final database = await service.database;
        final original = _workout(userId: 7, clientSyncId: 'shared-id');

        final firstId = await service.saveWorkoutInLocalDatabase(
          original,
          userId: 7,
        );
        final repeatedId = await service.saveWorkoutInLocalDatabase(
          original,
          userId: 7,
        );
        final otherOwnerId = await service.saveWorkoutInLocalDatabase(
          _workout(userId: 8, clientSyncId: 'shared-id'),
          userId: 8,
        );

        expect(repeatedId, firstId);
        expect(otherOwnerId, isNot(firstId));
        expect(
          await database.query(
            'workouts',
            where: 'client_sync_id = ?',
            whereArgs: <Object?>['shared-id'],
          ),
          hasLength(2),
        );

        await expectLater(
          service.saveWorkoutInLocalDatabase(
            _workout(
              userId: 7,
              clientSyncId: 'shared-id',
              startTime: DateTime.utc(2026, 7, 12),
            ),
            userId: 7,
          ),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          service.saveWorkoutInLocalDatabase(original, userId: 8),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('rejects orphan inserts and cascades every owned child row', () async {
      final service = await harness.openService();
      final database = await service.database;
      final ownerWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(userId: 7, clientSyncId: 'cascade-owner', withChildren: true),
        userId: 7,
      );
      final otherWorkoutId = await service.saveWorkoutInLocalDatabase(
        _workout(userId: 8, clientSyncId: 'cascade-other', withChildren: true),
        userId: 8,
      );
      await service.insertWorkoutImage(
        _image(ownerWorkoutId, 'owner-image'),
        userId: 7,
      );
      await service.insertWorkoutImage(
        _image(otherWorkoutId, 'other-image'),
        userId: 8,
      );

      await expectLater(
        database.insert('tracking_points', <String, Object?>{
          'workout_id': 999999,
          'latitude': 1.0,
          'longitude': 1.0,
          'timestamp': '2026-07-11T10:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      await service.deleteWorkoutFromLocalDatabase(ownerWorkoutId, userId: 8);
      expect(await _rowCount(database, 'workouts', ownerWorkoutId), 1);

      await service.deleteWorkoutFromLocalDatabase(ownerWorkoutId, userId: 7);

      expect(await _rowCount(database, 'workouts', ownerWorkoutId), 0);
      expect(await _childCount(database, 'tracking_points', ownerWorkoutId), 0);
      expect(await _childCount(database, 'status_changes', ownerWorkoutId), 0);
      expect(await _childCount(database, 'workout_images', ownerWorkoutId), 0);
      expect(await _rowCount(database, 'workouts', otherWorkoutId), 1);
      expect(await _childCount(database, 'tracking_points', otherWorkoutId), 1);
      expect(await _childCount(database, 'status_changes', otherWorkoutId), 1);
      expect(await _childCount(database, 'workout_images', otherWorkoutId), 1);
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });
}

WorkoutSessionEntity _workout({
  required int userId,
  required String clientSyncId,
  DateTime? startTime,
  bool withChildren = false,
}) {
  final startedAt = startTime ?? DateTime.utc(2026, 7, 11, 10);
  return WorkoutSessionEntity(
    clientSyncId: clientSyncId,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: startedAt,
    endTime: startedAt.add(const Duration(minutes: 30)),
    totalDistance: 5000,
    averageSpeed: 5000 / 1800,
    userId: userId,
    trackingPoints:
        withChildren
            ? <TrackingPointEntity>[
              TrackingPointEntity(
                latitude: 1,
                longitude: 1,
                timestamp: startedAt.add(const Duration(minutes: 1)),
              ),
            ]
            : const <TrackingPointEntity>[],
    statusChanges:
        withChildren
            ? <StatusChangeEvent>[
              StatusChangeEvent(
                status: WorkoutStatus.completed,
                timestamp: startedAt.add(const Duration(minutes: 30)),
              ),
            ]
            : const <StatusChangeEvent>[],
  );
}

ActivityImageEntity _image(int workoutId, String clientImageId) {
  final now = DateTime.utc(2026, 7, 11, 11);
  return ActivityImageEntity(
    localWorkoutId: workoutId,
    clientImageId: clientImageId,
    localPath: '/test/$clientImageId.jpg',
    thumbnailPath: '/test/$clientImageId-thumb.jpg',
    contentType: 'image/jpeg',
    sizeBytes: 10,
    status: ActivityImageSyncStatus.queued,
    createdAt: now,
    updatedAt: now,
  );
}

Future<int> _pragmaInt(Database database, String pragma) async {
  final rows = await database.rawQuery('PRAGMA $pragma');
  return (rows.single.values.single as num).toInt();
}

Future<int> _rowCount(Database database, String table, int id) async {
  final rows = await database.rawQuery(
    'SELECT COUNT(*) AS count FROM $table WHERE id = ?',
    <Object?>[id],
  );
  return (rows.single['count'] as num).toInt();
}

Future<int> _childCount(Database database, String table, int workoutId) async {
  final rows = await database.rawQuery(
    'SELECT COUNT(*) AS count FROM $table WHERE workout_id = ?',
    <Object?>[workoutId],
  );
  return (rows.single['count'] as num).toInt();
}

Future<void> _expectIndex(
  Database database, {
  required String table,
  required String name,
  required List<({String name, bool descending})> columns,
  bool unique = false,
}) async {
  final indexes = await database.rawQuery('PRAGMA index_list("$table")');
  final index = indexes.singleWhere((row) => row['name'] == name);
  expect(index['unique'], unique ? 1 : 0, reason: name);

  final metadata =
      (await database.rawQuery('PRAGMA index_xinfo("$name")'))
          .where((row) => row['key'] == 1 && (row['cid'] as num).toInt() >= 0)
          .toList()
        ..sort(
          (left, right) => (left['seqno'] as num).toInt().compareTo(
            (right['seqno'] as num).toInt(),
          ),
        );
  final actual =
      metadata
          .map(
            (row) => (
              name: row['name'] as String,
              descending: row['desc'] == 1,
            ),
          )
          .toList();
  expect(actual, columns, reason: name);
}
