import 'package:flutter_test/flutter_test.dart';
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

  group('metrics version schema', () {
    test('fresh databases persist new workouts as metrics version 2', () async {
      final service = await harness.openService();
      final database = await service.database;
      final workout = WorkoutSessionEntity(
        clientSyncId: 'fresh-v2',
        type: WorkoutType.running,
        status: WorkoutStatus.completed,
        startTime: DateTime.utc(2026, 7, 11, 10),
        endTime: DateTime.utc(2026, 7, 11, 11),
        totalDistance: 10000,
        averageSpeed: 10000 / 3600,
        maxSpeed: 4.2,
        averagePace: 6,
        calories: 600,
        userId: 7,
      );

      expect(
        workout.metricsVersion,
        WorkoutSessionEntity.currentMetricsVersion,
      );
      expect(workout.copyWith().metricsVersion, workout.metricsVersion);

      final workoutId = await service.saveWorkoutInLocalDatabase(
        workout,
        userId: 7,
      );
      final storedRows = await database.query(
        'workouts',
        where: 'id = ?',
        whereArgs: <Object?>[workoutId],
      );
      final columns = await database.rawQuery('PRAGMA table_info(workouts)');
      final metricsVersionColumn = columns.singleWhere(
        (column) => column['name'] == 'metrics_version',
      );

      expect(await database.getVersion(), 6);
      expect(metricsVersionColumn['notnull'], 1);
      expect(metricsVersionColumn['dflt_value'].toString(), '1');
      expect(
        storedRows.single['metrics_version'],
        WorkoutSessionEntity.currentMetricsVersion,
      );

      final loaded = await service.getWorkoutFromLocalDatabase(
        workoutId,
        userId: 7,
      );
      expect(loaded, isNotNull);
      expect(
        loaded!.metricsVersion,
        WorkoutSessionEntity.currentMetricsVersion,
      );

      final negativePauseId = await service.saveWorkoutInLocalDatabase(
        workout.copyWith(
          clientSyncId: 'fresh-negative-pause',
          pausedDuration: const Duration(seconds: -60),
        ),
        userId: 7,
      );
      final overlongPauseId = await service.saveWorkoutInLocalDatabase(
        workout.copyWith(
          clientSyncId: 'fresh-overlong-pause',
          pausedDuration: const Duration(hours: 2),
        ),
        userId: 7,
      );
      final normalizedPauseRows = await database.query(
        'workouts',
        columns: <String>['id', 'paused_duration'],
        where: 'id IN (?, ?)',
        whereArgs: <Object?>[negativePauseId, overlongPauseId],
        orderBy: 'id ASC',
      );

      expect(normalizedPauseRows, <Map<String, Object?>>[
        <String, Object?>{'id': negativePauseId, 'paused_duration': 0},
        <String, Object?>{'id': overlongPauseId, 'paused_duration': 3600},
      ]);
      expect(
        (await service.getWorkoutFromLocalDatabase(
          negativePauseId,
          userId: 7,
        ))!.activeDuration,
        const Duration(hours: 1),
      );
      expect(
        (await service.getWorkoutFromLocalDatabase(
          overlongPauseId,
          userId: 7,
        ))!.activeDuration,
        Duration.zero,
      );

      expect(
        WorkoutSessionEntity.isSupportedMetricsVersion(
          WorkoutSessionEntity.legacyMetricsVersion,
        ),
        isTrue,
      );
      expect(
        WorkoutSessionEntity.isSupportedMetricsVersion(
          WorkoutSessionEntity.currentMetricsVersion,
        ),
        isTrue,
      );
      expect(WorkoutSessionEntity.isSupportedMetricsVersion(3), isFalse);

      await expectLater(
        service.saveWorkoutInLocalDatabase(
          workout.copyWith(metricsVersion: 3),
          userId: 7,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        database.insert(
          'workouts',
          _workoutRow(
            clientSyncId: 'fresh-invalid-version',
            startTime: '2026-07-11T14:00:00.000Z',
            endTime: '2026-07-11T14:10:00.000Z',
            metricsVersion: 3,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'version 4 upgrades tag legacy rows once without rewriting metrics',
      () async {
        final legacyDatabase = await harness.createVersion4Database();
        final legacyId = await legacyDatabase.insert(
          'workouts',
          _workoutRow(
            clientSyncId: 'legacy-valid',
            startTime: '2026-07-11T10:00:00.000Z',
            endTime: '2026-07-11T11:00:00.000Z',
            pausedDuration: 600,
            totalDistance: 10000,
            averageSpeed: 36,
            maxSpeed: 44.5,
            averagePace: 6,
            calories: 700,
          ),
        );
        final zeroDurationId = await legacyDatabase.insert(
          'workouts',
          _workoutRow(
            clientSyncId: 'legacy-zero-duration',
            startTime: '2026-07-11T12:00:00.000Z',
            endTime: '2026-07-11T12:00:00.000Z',
            pausedDuration: 0,
            totalDistance: 1250,
            averageSpeed: 999,
            maxSpeed: 1001,
            averagePace: 0,
            calories: 123,
          ),
        );
        await legacyDatabase.close();

        final service = await harness.openService();
        final database = await service.database;
        final upgradedRows = await database.query(
          'workouts',
          orderBy: 'id ASC',
        );

        expect(await database.getVersion(), 6);
        expect(
          upgradedRows.map((row) => row['metrics_version']),
          everyElement(WorkoutSessionEntity.legacyMetricsVersion),
        );
        expect(upgradedRows.first['total_distance'], 10000.0);
        expect(upgradedRows.first['average_speed'], 36.0);
        expect(upgradedRows.first['max_speed'], 44.5);
        expect(upgradedRows.first['average_pace'], 6.0);
        expect(upgradedRows.first['calories'], 700);
        expect(upgradedRows.last['average_speed'], 999.0);
        expect(upgradedRows.last['max_speed'], 1001.0);
        expect(upgradedRows.last['calories'], 123);
        expect((upgradedRows.last['average_speed']! as num).isFinite, isTrue);

        await expectLater(
          database.insert(
            'workouts',
            _workoutRow(
              clientSyncId: 'upgraded-invalid-version',
              startTime: '2026-07-11T14:00:00.000Z',
              endTime: '2026-07-11T14:10:00.000Z',
              metricsVersion: 3,
            ),
          ),
          throwsA(isA<DatabaseException>()),
        );

        final legacyWorkout = await service.getWorkoutFromLocalDatabase(
          legacyId,
          userId: 7,
        );
        final zeroDurationWorkout = await service.getWorkoutFromLocalDatabase(
          zeroDurationId,
          userId: 7,
        );
        expect(
          legacyWorkout!.metricsVersion,
          WorkoutSessionEntity.legacyMetricsVersion,
        );
        expect(legacyWorkout.averageSpeed, 36.0);
        expect(
          zeroDurationWorkout!.metricsVersion,
          WorkoutSessionEntity.legacyMetricsVersion,
        );
        expect(zeroDurationWorkout.averageSpeed, 999.0);

        await database.insert(
          'workouts',
          _workoutRow(
            clientSyncId: 'already-v2',
            startTime: '2026-07-11T13:00:00.000Z',
            endTime: '2026-07-11T13:10:00.000Z',
            pausedDuration: 0,
            totalDistance: 1000,
            averageSpeed: 1000 / 600,
            maxSpeed: 2.5,
            averagePace: 10,
            calories: 100,
            metricsVersion: WorkoutSessionEntity.currentMetricsVersion,
          ),
        );
        final beforeReopen = await database.query(
          'workouts',
          orderBy: 'id ASC',
        );
        await service.close();

        final reopenedService = await harness.openService();
        final reopenedDatabase = await reopenedService.database;
        final afterReopen = await reopenedDatabase.query(
          'workouts',
          orderBy: 'id ASC',
        );

        expect(afterReopen, beforeReopen);
        expect(afterReopen.map((row) => row['metrics_version']), <int>[
          WorkoutSessionEntity.legacyMetricsVersion,
          WorkoutSessionEntity.legacyMetricsVersion,
          WorkoutSessionEntity.currentMetricsVersion,
        ]);
      },
    );
  });

  group('active-duration statistics', () {
    test('entity active duration uses the same non-negative clamp', () {
      final start = DateTime.utc(2026, 7, 11, 10);
      final pauseLongerThanWall = WorkoutSessionEntity(
        clientSyncId: 'pause-longer-than-wall',
        type: WorkoutType.running,
        status: WorkoutStatus.completed,
        startTime: start,
        endTime: start.add(const Duration(minutes: 10)),
        pausedDuration: const Duration(minutes: 15),
        userId: 7,
      );
      final endBeforeStart = WorkoutSessionEntity(
        clientSyncId: 'end-before-start',
        type: WorkoutType.running,
        status: WorkoutStatus.completed,
        startTime: start,
        endTime: start.subtract(const Duration(minutes: 1)),
        userId: 7,
      );
      final negativePause = WorkoutSessionEntity(
        clientSyncId: 'negative-pause',
        type: WorkoutType.running,
        status: WorkoutStatus.completed,
        startTime: start,
        endTime: start.add(const Duration(minutes: 10)),
        pausedDuration: const Duration(seconds: -60),
        userId: 7,
      );

      expect(
        pauseLongerThanWall.wallClockDuration,
        const Duration(minutes: 10),
      );
      expect(
        pauseLongerThanWall.effectivePausedDuration,
        const Duration(minutes: 10),
      );
      expect(pauseLongerThanWall.activeDuration, Duration.zero);
      expect(endBeforeStart.wallClockDuration, Duration.zero);
      expect(endBeforeStart.effectivePausedDuration, Duration.zero);
      expect(endBeforeStart.activeDuration, Duration.zero);
      expect(negativePause.wallClockDuration, const Duration(minutes: 10));
      expect(negativePause.effectivePausedDuration, Duration.zero);
      expect(negativePause.activeDuration, const Duration(minutes: 10));
    });

    test(
      'overall and per-type totals subtract and clamp paused duration',
      () async {
        final service = await harness.openService();
        final database = await service.database;

        final fixtures = <Map<String, Object?>>[
          _workoutRow(
            clientSyncId: 'run-paused',
            startTime: '2026-07-11T10:00:00.000Z',
            endTime: '2026-07-11T11:00:00.000Z',
            pausedDuration: 600,
            type: 'running',
          ),
          _workoutRow(
            clientSyncId: 'run-no-pause',
            startTime: '2026-07-11T12:00:00.000Z',
            endTime: '2026-07-11T12:10:00.000Z',
            pausedDuration: null,
            type: 'running',
          ),
          _workoutRow(
            clientSyncId: 'walk-paused',
            startTime: '2026-07-11T13:00:00.000Z',
            endTime: '2026-07-11T13:30:00.000Z',
            pausedDuration: 300,
            type: 'walking',
          ),
          _workoutRow(
            clientSyncId: 'pause-longer-than-wall',
            startTime: '2026-07-11T14:00:00.000Z',
            endTime: '2026-07-11T14:10:00.000Z',
            pausedDuration: 900,
            type: 'cycling',
          ),
          _workoutRow(
            clientSyncId: 'end-before-start',
            startTime: '2026-07-11T15:00:00.000Z',
            endTime: '2026-07-11T14:00:00.000Z',
            pausedDuration: 0,
            type: 'hiking',
          ),
          _workoutRow(
            clientSyncId: 'invalid-date',
            startTime: 'invalid-start',
            endTime: 'invalid-end',
            pausedDuration: 60,
            type: 'hiking',
          ),
          _workoutRow(
            clientSyncId: 'negative-pause',
            startTime: '2026-07-11T16:00:00.000Z',
            endTime: '2026-07-11T16:09:40.000Z',
            pausedDuration: -60,
            type: 'walking',
          ),
          _workoutRow(
            clientSyncId: 'incomplete',
            startTime: '2026-07-11T17:00:00.000Z',
            endTime: null,
            pausedDuration: 0,
            type: 'cycling',
          ),
          _workoutRow(
            clientSyncId: 'other-user',
            startTime: '2026-07-11T18:00:00.000Z',
            endTime: '2026-07-11T20:00:00.000Z',
            pausedDuration: 0,
            userId: 99,
          ),
          _workoutRow(
            clientSyncId: 'deleted',
            startTime: '2026-07-11T18:00:00.000Z',
            endTime: '2026-07-11T20:00:00.000Z',
            pausedDuration: 0,
            deletedLocally: 1,
          ),
        ];

        for (final fixture in fixtures) {
          await database.insert('workouts', fixture);
        }

        final overall = await service.getWorkoutStatistics(7);
        final running = await service.getWorkoutStatistics(
          7,
          workoutType: 'running',
        );
        final byType = await service.getWorkoutStatisticsByType(7);

        expect(overall.totalWorkouts, 8);
        expect(overall.totalDuration, const Duration(seconds: 5680));
        expect(overall.averageDuration, const Duration(seconds: 710));

        expect(running.totalWorkouts, 2);
        expect(running.totalDuration, const Duration(seconds: 3600));
        expect(running.averageDuration, const Duration(seconds: 1800));

        expect(
          byType.keys,
          containsAll(<String>['running', 'walking', 'cycling', 'hiking']),
        );
        expect(byType['running']!.totalDuration, const Duration(seconds: 3600));
        expect(
          byType['running']!.averageDuration,
          const Duration(seconds: 1800),
        );
        expect(byType['walking']!.totalDuration, const Duration(seconds: 2080));
        expect(
          byType['walking']!.averageDuration,
          const Duration(seconds: 1040),
        );
        expect(byType['cycling']!.totalDuration, Duration.zero);
        expect(byType['hiking']!.totalDuration, Duration.zero);
      },
    );
  });
}

Map<String, Object?> _workoutRow({
  required String clientSyncId,
  required String startTime,
  required String? endTime,
  int? pausedDuration,
  String type = 'running',
  int userId = 7,
  int deletedLocally = 0,
  double totalDistance = 100,
  double averageSpeed = 1,
  double maxSpeed = 2,
  double? averagePace = 10,
  int? calories = 50,
  int? metricsVersion,
}) {
  return <String, Object?>{
    'type': type,
    'status': 'completed',
    'start_time': startTime,
    'end_time': endTime,
    'paused_duration': pausedDuration,
    if (metricsVersion != null) 'metrics_version': metricsVersion,
    'total_distance': totalDistance,
    'average_speed': averageSpeed,
    'max_speed': maxSpeed,
    'average_pace': averagePace,
    'calories': calories,
    'elevation_gain': 0.0,
    'elevation_loss': 0.0,
    'user_id': userId,
    'name': clientSyncId,
    'notes': null,
    'remote_activity_id': null,
    'client_sync_id': clientSyncId,
    'deleted_locally': deletedLocally,
    'synced': 0,
  };
}
