import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/local_db_test_harness.dart';

void main() {
  setUpAll(LocalDbTestHarness.initializeFfi);

  group('version 6 migration', () {
    for (final variant in LegacyDatabaseVariant.values) {
      test('${variant.name} preserves valid data, removes child orphans, and '
          'reopens idempotently', () async {
        final harness = await LocalDbTestHarness.create();
        addTearDown(harness.dispose);
        final legacyDatabase = await harness.createLegacyDatabase(variant);
        final expectedMetricsVersion = variant.hasMetricsVersion ? 2 : 1;

        await legacyDatabase.insert(
          'workouts',
          _legacyWorkoutRow(
            variant,
            id: 101,
            userId: 7,
            clientSyncId:
                variant.hasNullableClientSyncId ? null : 'legacy-owner',
            metricsVersion: expectedMetricsVersion,
          ),
        );
        await legacyDatabase.insert(
          'tracking_points',
          _trackingPointRow(id: 1, workoutId: 101),
        );
        await legacyDatabase.insert(
          'tracking_points',
          _trackingPointRow(id: 2, workoutId: 999001),
        );

        if (variant.hasStatusChanges) {
          await legacyDatabase.insert(
            'status_changes',
            _statusChangeRow(id: 1, workoutId: 101),
          );
          await legacyDatabase.insert(
            'status_changes',
            _statusChangeRow(id: 2, workoutId: 999002),
          );
        }

        if (variant.hasImages) {
          await legacyDatabase.insert(
            'workout_images',
            _imageRow(id: 1, workoutId: 101, clientImageId: 'valid-image'),
          );
          await legacyDatabase.insert(
            'workout_images',
            _imageRow(id: 2, workoutId: 999003, clientImageId: 'orphan-image'),
          );
        }

        if (variant.hasDeleteSupport) {
          await legacyDatabase.insert(
            'workout_delete_queue',
            _deleteQueueRow(
              id: 1,
              localWorkoutId: 101,
              remoteActivityId: 501,
              userId: 999,
            ),
          );
          await legacyDatabase.insert(
            'workout_delete_queue',
            _deleteQueueRow(
              id: 2,
              localWorkoutId: 999004,
              remoteActivityId: 502,
              userId: 8,
            ),
          );
        }
        await legacyDatabase.close();

        final service = await harness.openService();
        final database = await service.database;

        expect(await database.getVersion(), 6);
        expect(await _pragmaInt(database, 'foreign_keys'), 1);
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        final workouts = await database.query(
          'workouts',
          where: 'id = ?',
          whereArgs: <Object?>[101],
        );
        expect(workouts, hasLength(1));
        expect(workouts.single['user_id'], 7);
        expect(workouts.single['total_distance'], 1234.0);
        expect(workouts.single['average_speed'], 3.5);
        expect(workouts.single['metrics_version'], expectedMetricsVersion);
        expect(workouts.single['sync_blocked_reason'], isNull);
        expect(
          (workouts.single['client_sync_id'] as String).trim(),
          isNotEmpty,
        );

        expect(await _childIds(database, 'tracking_points', 101), <int>[1]);
        expect(
          await _countWhere(
            database,
            'tracking_points',
            'workout_id = ?',
            <Object?>[999001],
          ),
          0,
        );

        final statusIds = await _childIds(database, 'status_changes', 101);
        expect(statusIds, variant.hasStatusChanges ? <int>[1] : isEmpty);
        expect(
          await _countWhere(
            database,
            'status_changes',
            'workout_id = ?',
            <Object?>[999002],
          ),
          0,
        );

        final imageIds = await _childIds(database, 'workout_images', 101);
        expect(imageIds, variant.hasImages ? <int>[1] : isEmpty);
        expect(
          await _countWhere(
            database,
            'workout_images',
            'workout_id = ?',
            <Object?>[999003],
          ),
          0,
        );

        final queues = await database.query(
          'workout_delete_queue',
          orderBy: 'id ASC',
        );
        if (variant.hasDeleteSupport) {
          expect(queues, hasLength(2));
          expect(queues.first['user_id'], 7);
          expect(queues.last['local_workout_id'], 999004);
          expect(queues.last['user_id'], 8);
        } else {
          expect(queues, isEmpty);
        }

        final requiredIndexes = <String>{
          'idx_workouts_user_start_time',
          'idx_workouts_user_client_sync_id',
          'idx_tracking_points_workout_timestamp',
          'idx_status_changes_workout_timestamp',
        };
        final actualIndexes = <String>{
          for (final table in <String>[
            'workouts',
            'tracking_points',
            'status_changes',
          ])
            for (final row in await database.rawQuery(
              'PRAGMA index_list("$table")',
            ))
              row['name'] as String,
        };
        expect(actualIndexes, containsAll(requiredIndexes));

        final beforeReopen = await _migrationSnapshot(database);
        await service.close();
        final reopenedService = await harness.openService();
        final reopenedDatabase = await reopenedService.database;
        expect(await _pragmaInt(reopenedDatabase, 'foreign_keys'), 1);
        expect(await _migrationSnapshot(reopenedDatabase), beforeReopen);
        expect(
          await reopenedDatabase.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      });
    }

    test(
      'quarantines a resolvable duplicate without making it uploadable',
      () async {
        final harness = await LocalDbTestHarness.create();
        addTearDown(harness.dispose);
        final legacyDatabase = await harness.createLegacyDatabase(
          LegacyDatabaseVariant.version5,
        );
        await legacyDatabase.insert(
          'workouts',
          _legacyWorkoutRow(
            LegacyDatabaseVariant.version5,
            id: 1,
            userId: 7,
            clientSyncId: 'duplicate-id',
            metricsVersion: 2,
            remoteActivityId: 7001,
            synced: 1,
          ),
        );
        await legacyDatabase.insert(
          'workouts',
          _legacyWorkoutRow(
            LegacyDatabaseVariant.version5,
            id: 2,
            userId: 7,
            clientSyncId: 'duplicate-id',
            metricsVersion: 2,
          ),
        );
        await legacyDatabase.insert(
          'workouts',
          _legacyWorkoutRow(
            LegacyDatabaseVariant.version5,
            id: 3,
            userId: 8,
            clientSyncId: 'duplicate-id',
            metricsVersion: 2,
          ),
        );
        await legacyDatabase.close();

        final service = await harness.openService();
        final database = await service.database;
        final rows = await database.query('workouts', orderBy: 'id ASC');

        expect(rows[0]['client_sync_id'], 'duplicate-id');
        expect(rows[0]['sync_blocked_reason'], isNull);
        expect(rows[1]['client_sync_id'], isNot('duplicate-id'));
        expect(rows[1]['sync_blocked_reason'], 'duplicate_client_sync_id');
        expect(rows[1]['synced'], 0);
        expect(rows[2]['client_sync_id'], 'duplicate-id');
        expect(rows[2]['sync_blocked_reason'], isNull);
        expect(await service.getUnsyncedWorkoutsFromLocalDatabase(7), isEmpty);
        expect(
          await service.getUnsyncedWorkoutsFromLocalDatabase(8),
          hasLength(1),
        );
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);

        final beforeReopen = await database.query(
          'workouts',
          orderBy: 'id ASC',
        );
        await service.close();
        final reopened = await harness.openService();
        expect(
          await (await reopened.database).query('workouts', orderBy: 'id ASC'),
          beforeReopen,
        );
      },
    );

    test(
      'ambiguous duplicate remote identities roll back the entire upgrade',
      () async {
        final harness = await LocalDbTestHarness.create();
        addTearDown(harness.dispose);
        final legacyDatabase = await harness.createLegacyDatabase(
          LegacyDatabaseVariant.version5,
        );
        await legacyDatabase.insert(
          'workouts',
          _legacyWorkoutRow(
            LegacyDatabaseVariant.version5,
            id: 1,
            userId: 7,
            clientSyncId: 'ambiguous-id',
            metricsVersion: 2,
            remoteActivityId: 7001,
            synced: 1,
          ),
        );
        await legacyDatabase.insert(
          'workouts',
          _legacyWorkoutRow(
            LegacyDatabaseVariant.version5,
            id: 2,
            userId: 7,
            clientSyncId: 'ambiguous-id',
            metricsVersion: 2,
            remoteActivityId: 7002,
            synced: 1,
          ),
        );
        await legacyDatabase.insert(
          'tracking_points',
          _trackingPointRow(id: 1, workoutId: 1),
        );
        final before = await _migrationSnapshot(legacyDatabase);
        await legacyDatabase.close();

        await expectLater(harness.openService(), throwsA(isA<StateError>()));

        final rawDatabase = await harness.openRawDatabase();
        expect(await rawDatabase.getVersion(), 5);
        expect(await _migrationSnapshot(rawDatabase), before);
        final columns = await rawDatabase.rawQuery(
          'PRAGMA table_info(workouts)',
        );
        expect(
          columns.where((column) => column['name'] == 'sync_blocked_reason'),
          isEmpty,
        );
        final indexes = await rawDatabase.rawQuery(
          'PRAGMA index_list(workouts)',
        );
        expect(
          indexes.where(
            (index) => index['name'] == 'idx_workouts_user_client_sync_id',
          ),
          isEmpty,
        );
      },
    );
  });
}

Map<String, Object?> _legacyWorkoutRow(
  LegacyDatabaseVariant variant, {
  required int id,
  required int userId,
  required String? clientSyncId,
  required int metricsVersion,
  int? remoteActivityId,
  int synced = 0,
}) {
  return <String, Object?>{
    'id': id,
    'type': 'running',
    'status': 'completed',
    'start_time': '2026-07-11T10:00:00.000Z',
    'end_time': '2026-07-11T10:30:00.000Z',
    'paused_duration': 30,
    if (variant.hasMetricsVersion) 'metrics_version': metricsVersion,
    'total_distance': 1234.0,
    'average_speed': 3.5,
    'max_speed': 4.0,
    'average_pace': 5.5,
    'calories': 100,
    'elevation_gain': 12.0,
    'elevation_loss': 8.0,
    'user_id': userId,
    'name': 'legacy-workout-$id',
    'notes': 'fixture',
    if (variant.hasSyncColumns) 'remote_activity_id': remoteActivityId,
    if (variant.hasSyncColumns) 'client_sync_id': clientSyncId,
    if (variant.hasDeleteSupport) 'deleted_locally': 0,
    'created_at': '2026-07-11T10:31:00.000Z',
    'synced': synced,
  };
}

Map<String, Object?> _trackingPointRow({
  required int id,
  required int workoutId,
}) {
  return <String, Object?>{
    'id': id,
    'workout_id': workoutId,
    'latitude': 1.0,
    'longitude': 1.0,
    'altitude': 2.0,
    'accuracy': 3.0,
    'speed': 4.0,
    'heading': 5.0,
    'timestamp': '2026-07-11T10:01:00.000Z',
  };
}

Map<String, Object?> _statusChangeRow({
  required int id,
  required int workoutId,
}) {
  return <String, Object?>{
    'id': id,
    'workout_id': workoutId,
    'status': 'completed',
    'timestamp': '2026-07-11T10:30:00.000Z',
  };
}

Map<String, Object?> _imageRow({
  required int id,
  required int workoutId,
  required String clientImageId,
}) {
  return <String, Object?>{
    'id': id,
    'workout_id': workoutId,
    'remote_activity_id': null,
    'remote_image_id': null,
    'client_image_id': clientImageId,
    'local_path': '/test/$clientImageId.jpg',
    'thumbnail_path': '/test/$clientImageId-thumb.jpg',
    'remote_url': null,
    'remote_url_expires_at': null,
    's3_key': null,
    'content_type': 'image/jpeg',
    'size_bytes': 10,
    'checksum_sha256': null,
    'width': 10,
    'height': 10,
    'sort_order': 0,
    'caption': null,
    'status': 'queued',
    'retry_count': 0,
    'last_error': null,
    'next_retry_at': null,
    'created_at': '2026-07-11T10:31:00.000Z',
    'updated_at': '2026-07-11T10:31:00.000Z',
  };
}

Map<String, Object?> _deleteQueueRow({
  required int id,
  required int localWorkoutId,
  required int remoteActivityId,
  required int userId,
}) {
  return <String, Object?>{
    'id': id,
    'local_workout_id': localWorkoutId,
    'remote_activity_id': remoteActivityId,
    'user_id': userId,
    'status': 'queued',
    'retry_count': 0,
    'last_error': null,
    'next_retry_at': null,
    'created_at': '2026-07-11T10:31:00.000Z',
    'updated_at': '2026-07-11T10:31:00.000Z',
  };
}

Future<int> _pragmaInt(Database database, String pragma) async {
  final rows = await database.rawQuery('PRAGMA $pragma');
  return (rows.single.values.single as num).toInt();
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

Future<List<int>> _childIds(
  Database database,
  String table,
  int workoutId,
) async {
  final rows = await database.query(
    table,
    columns: <String>['id'],
    where: 'workout_id = ?',
    whereArgs: <Object?>[workoutId],
    orderBy: 'id ASC',
  );
  return rows.map((row) => (row['id'] as num).toInt()).toList();
}

Future<Map<String, Object?>> _migrationSnapshot(Database database) async {
  return <String, Object?>{
    'workouts': await database.query('workouts', orderBy: 'id ASC'),
    'tracking_points': await database.query(
      'tracking_points',
      orderBy: 'id ASC',
    ),
    if (await _tableExists(database, 'status_changes'))
      'status_changes': await database.query(
        'status_changes',
        orderBy: 'id ASC',
      ),
    if (await _tableExists(database, 'workout_images'))
      'workout_images': await database.query(
        'workout_images',
        orderBy: 'id ASC',
      ),
    if (await _tableExists(database, 'workout_delete_queue'))
      'workout_delete_queue': await database.query(
        'workout_delete_queue',
        orderBy: 'id ASC',
      ),
  };
}

Future<bool> _tableExists(Database database, String table) async {
  final rows = await database.query(
    'sqlite_master',
    columns: <String>['name'],
    where: 'type = ? AND name = ?',
    whereArgs: <Object?>['table', table],
    limit: 1,
  );
  return rows.isNotEmpty;
}
