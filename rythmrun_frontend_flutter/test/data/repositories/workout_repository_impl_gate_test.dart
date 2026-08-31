import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/workout_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/workout_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/registration_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';

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

  test(
    'user-scope suspension waits for in-flight workout sync and blocks new sync',
    () async {
      const userId = 7;
      final service = await harness.openService();
      final localDataSource = WorkoutLocalDataSource(service);
      final remoteDataSource = _BlockingActivityRemoteDataSource();
      final gate = UserScopeOperationGate()..activate(userId);
      final repository = WorkoutRepositoryImpl(
        localDataSource,
        _FakeAuthRepository(userId),
        remoteDataSource,
        operationGate: gate,
      );
      await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'first', userId: userId),
        userId: userId,
      );

      final reachedRemote = Completer<void>();
      final allowRemote = Completer<void>();
      remoteDataSource
        ..reachedRemote = reachedRemote
        ..allowRemote = allowRemote;

      final sync = repository.syncWorkouts();
      await reachedRemote.future;

      var didDrain = false;
      final drain = gate.suspendAndDrain().then((_) {
        didDrain = true;
      });
      await _pumpMicrotasks();

      expect(didDrain, isFalse);
      expect(gate.tryAcquire(userId), isNull);

      allowRemote.complete();
      await sync;
      await drain;
      expect(didDrain, isTrue);

      await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'second', userId: userId),
        userId: userId,
      );
      final callsBeforeSuspendedSync = remoteDataSource.createCalls;

      await repository.syncWorkouts();

      expect(remoteDataSource.createCalls, callsBeforeSuspendedSync);

      remoteDataSource
        ..reachedRemote = null
        ..allowRemote = null;
      gate.activate(userId);
      await repository.syncWorkouts();

      expect(
        remoteDataSource.createCalls,
        greaterThan(callsBeforeSuspendedSync),
      );
    },
  );

  test(
    'retained A work syncs and deletes once after forced A-B-A exit',
    () async {
      const userA = 7;
      const userB = 8;
      final service = await harness.openService();
      final remoteDataSource = _BlockingActivityRemoteDataSource();
      final authRepository = _FakeAuthRepository(userA);
      final operationGate = UserScopeOperationGate()..activate(userA);
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        authRepository,
        remoteDataSource,
        operationGate: operationGate,
      );
      final now = DateTime.utc(2026, 8, 31, 6);

      final syncedWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(
          clientSyncId: 'retained-synced',
          userId: userA,
          remoteActivityId: 7001,
        ).copyWith(
          trackingPoints: <TrackingPointEntity>[
            TrackingPointEntity(
              latitude: 12.0,
              longitude: 77.0,
              timestamp: now,
            ),
          ],
          statusChanges: <StatusChangeEvent>[
            StatusChangeEvent(status: WorkoutStatus.completed, timestamp: now),
          ],
        ),
        userId: userA,
      );
      await service.insertWorkoutImage(
        ActivityImageEntity(
          localWorkoutId: syncedWorkoutId,
          clientImageId: 'retained-image',
          localPath: '/synthetic/retained-image.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 128,
          status: ActivityImageSyncStatus.queued,
          createdAt: now,
          updatedAt: now,
        ),
        userId: userA,
      );
      await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'retained-upload', userId: userA),
        userId: userA,
      );
      final blockedWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'retained-blocked', userId: userA),
        userId: userA,
      );
      await service.markWorkoutSyncBlocked(
        userId: userA,
        localWorkoutId: blockedWorkoutId,
        clientSyncId: 'retained-blocked',
        reason: 'ACTIVITY_DOMAIN_INVALID',
      );
      final deletePendingWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(
          clientSyncId: 'retained-delete',
          userId: userA,
          remoteActivityId: 7002,
        ),
        userId: userA,
      );
      await service.deleteWorkoutFromLocalDatabase(
        deletePendingWorkoutId,
        userId: userA,
      );
      await service.saveWorkoutInLocalDatabase(
        _completedWorkout(
          clientSyncId: 'owner-b',
          userId: userB,
          remoteActivityId: 8001,
        ),
        userId: userB,
      );

      int? activeUserId = userA;
      final teardown = DefaultUserScopeTeardown(
        hasActiveWorkout: () => false,
        hasUnsavedWorkout: () => false,
        hasPendingTrackingCleanup: () => false,
        quiesceTrackingOperations: () async => true,
        finishWorkout: () async => true,
        retryWorkoutSave: () async => true,
        retryTrackingCleanup: () async => true,
        discardWorkout: () async {},
        suspendAndDrainWork: operationGate.suspendAndDrain,
        invalidateUserState: () async {
          final oldUserId = activeUserId;
          if (oldUserId == null) {
            throw StateError('No active owner to invalidate.');
          }
          await repository.setHistoryRestored(oldUserId, false);
          activeUserId = null;
        },
        activateWork: (userId) {
          final numericUserId = int.parse(userId);
          authRepository.currentUserId = numericUserId;
          operationGate.activate(numericUserId);
          activeUserId = numericUserId;
        },
      );

      final forcedExit = await teardown.teardown(
        reason: UserScopeExitReason.forcedAuthenticationLoss,
      );
      expect(forcedExit.isCompleted, isTrue);
      expect(authRepository.historyResetUserIds, <int>[userA]);

      final database = await service.database;
      expect(
        await database.query(
          'workouts',
          where: 'user_id = ?',
          whereArgs: <Object?>[userA],
        ),
        hasLength(4),
      );
      expect(
        await database.query(
          'tracking_points',
          where: 'workout_id = ?',
          whereArgs: <Object?>[syncedWorkoutId],
        ),
        hasLength(1),
      );
      expect(
        await database.query(
          'status_changes',
          where: 'workout_id = ?',
          whereArgs: <Object?>[syncedWorkoutId],
        ),
        hasLength(1),
      );
      expect(
        await database.query(
          'workout_images',
          where: 'workout_id = ?',
          whereArgs: <Object?>[syncedWorkoutId],
        ),
        hasLength(1),
      );
      expect(
        await database.query(
          'workout_delete_queue',
          where: 'user_id = ?',
          whereArgs: <Object?>[userA],
        ),
        hasLength(1),
      );

      teardown.activateUserScope('$userB');
      expect(await repository.getWorkout(syncedWorkoutId), isNull);
      expect(
        await service.getWorkoutImages(syncedWorkoutId, userId: userB),
        isEmpty,
      );
      expect(remoteDataSource.createCalls, 0);
      expect(remoteDataSource.deleteCalls, 0);
      expect(remoteDataSource.deletedActivityIds, isEmpty);

      final bExit = await teardown.teardown(
        reason: UserScopeExitReason.accountSwitch,
      );
      expect(bExit.isCompleted, isTrue);
      expect(remoteDataSource.createCalls, 0);
      expect(remoteDataSource.deleteCalls, 0);
      teardown.activateUserScope('$userA');

      await repository.syncWorkouts();
      await repository.syncWorkouts();

      expect(remoteDataSource.createCalls, 1);
      expect(remoteDataSource.deleteCalls, 1);
      expect(remoteDataSource.deletedActivityIds, <int>[7002]);
      expect(remoteDataSource.attemptedClientSyncIds, <String>[
        'retained-upload',
      ]);
      expect(authRepository.historyResetUserIds, <int>[userA, userB]);
      expect(
        await service.getUnsyncedWorkoutsFromLocalDatabase(userA),
        isEmpty,
      );
      final blockedRows = await database.query(
        'workouts',
        columns: <String>['sync_blocked_reason'],
        where: 'id = ?',
        whereArgs: <Object?>[blockedWorkoutId],
      );
      expect(
        blockedRows.single['sync_blocked_reason'],
        'ACTIVITY_DOMAIN_INVALID',
      );
      expect(
        await database.query(
          'workout_delete_queue',
          where: 'user_id = ?',
          whereArgs: <Object?>[userA],
        ),
        isEmpty,
      );
    },
  );

  test('forced finish-and-exit writes one durable completed workout', () async {
    const userId = 7;
    final service = await harness.openService();
    final remoteDataSource = _BlockingActivityRemoteDataSource();
    final authRepository = _FakeAuthRepository(userId);
    final operationGate = UserScopeOperationGate()..activate(userId);
    final workoutRepository = WorkoutRepositoryImpl(
      WorkoutLocalDataSource(service),
      authRepository,
      remoteDataSource,
      operationGate: operationGate,
    );
    final trackingRepository = _ExitLiveTrackingRepository(
      DateTime.utc(2026, 8, 31, 6),
    );
    final liveNotifier = LiveTrackingNotifier(
      trackingRepository,
      workoutRepository,
      currentUserId: () => authRepository.currentUserId,
      periodicTimerFactory: (_, _) => _NoopTimer(),
    );
    addTearDown(liveNotifier.dispose);

    await liveNotifier.startWorkout(WorkoutType.running);
    expect(liveNotifier.state.hasActiveSession, isTrue);
    trackingRepository.currentTime = DateTime.utc(2026, 8, 31, 6, 10);

    final teardown = DefaultUserScopeTeardown(
      hasActiveWorkout: () => liveNotifier.state.hasActiveSession,
      hasUnsavedWorkout: () => liveNotifier.hasUnsavedCompletedWorkout,
      hasPendingTrackingCleanup: () => liveNotifier.hasPendingTrackingCleanup,
      quiesceTrackingOperations: liveNotifier.quiesceForAccountExit,
      finishWorkout: () async {
        final result = await liveNotifier.stopWorkout();
        return result.isDurablySaved &&
            !liveNotifier.hasUnsavedCompletedWorkout;
      },
      retryWorkoutSave: liveNotifier.retryUnsavedWorkoutSave,
      retryTrackingCleanup: liveNotifier.retryPendingTrackingCleanup,
      discardWorkout: () async {
        await liveNotifier.discardWorkout(forAccountExit: true);
      },
      suspendAndDrainWork: operationGate.suspendAndDrain,
      invalidateUserState:
          () => workoutRepository.setHistoryRestored(userId, false),
      activateWork: (_) {},
    );

    final result = await teardown.teardown(
      reason: UserScopeExitReason.forcedAuthenticationLoss,
    );

    expect(result.isCompleted, isTrue);
    final workouts = await service.getWorkoutsFromLocalDatabase(userId);
    expect(workouts, hasLength(1));
    expect(workouts.single.status, WorkoutStatus.completed);
    expect(workouts.single.endTime, trackingRepository.currentTime);
    expect(authRepository.historyResetUserIds, <int>[userId]);
  });

  test(
    'history reset targets its explicit owner despite current auth changes',
    () async {
      const ownerUserId = 7;
      final service = await harness.openService();
      final authRepository = _FakeAuthRepository(8);
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        authRepository,
        _BlockingActivityRemoteDataSource(),
      );

      await repository.setHistoryRestored(ownerUserId, false);
      authRepository.currentUserId = null;
      await repository.setHistoryRestored(ownerUserId, false);

      expect(authRepository.historyResetUserIds, <int>[
        ownerUserId,
        ownerUserId,
      ]);
    },
  );

  test(
    'owner change during remote create leaves the original row retryable',
    () async {
      const userA = 7;
      const userB = 8;
      final service = await harness.openService();
      final localDataSource = WorkoutLocalDataSource(service);
      final remoteDataSource = _BlockingActivityRemoteDataSource();
      final authRepository = _FakeAuthRepository(userA);
      final repository = WorkoutRepositoryImpl(
        localDataSource,
        authRepository,
        remoteDataSource,
      );
      final localWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'owner-race', userId: userA),
        userId: userA,
      );
      final reachedRemote = Completer<void>();
      final allowRemote = Completer<void>();
      remoteDataSource
        ..reachedRemote = reachedRemote
        ..allowRemote = allowRemote;

      final sync = repository.syncWorkouts();
      await reachedRemote.future;
      authRepository.currentUserId = userB;
      allowRemote.complete();
      await sync;

      final original = await service.getWorkoutFromLocalDatabase(
        localWorkoutId,
        userId: userA,
      );
      expect(original, isNotNull);
      expect(original!.remoteActivityId, isNull);
      expect(
        await service.getUnsyncedWorkoutsFromLocalDatabase(userA),
        hasLength(1),
      );
      expect(
        await service.getWorkoutFromLocalDatabase(
          localWorkoutId,
          userId: userB,
        ),
        isNull,
      );
    },
  );

  test(
    'permanent create rejection blocks only that owned row and continues',
    () async {
      const userId = 7;
      final service = await harness.openService();
      final localDataSource = WorkoutLocalDataSource(service);
      final remoteDataSource =
          _BlockingActivityRemoteDataSource()
            ..createErrorsByClientSyncId['permanent-invalid'] =
                const HttpStatusException(
                  422,
                  'Activity payload is invalid',
                  code: 'ACTIVITY_DOMAIN_INVALID',
                  retryable: false,
                );
      final repository = WorkoutRepositoryImpl(
        localDataSource,
        _FakeAuthRepository(userId),
        remoteDataSource,
      );
      final blockedId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'permanent-invalid', userId: userId),
        userId: userId,
      );
      final validId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: 'valid-after-block', userId: userId),
        userId: userId,
      );

      await repository.syncWorkouts();

      final database = await service.database;
      final rows = await database.query(
        'workouts',
        columns: <String>[
          'id',
          'synced',
          'remote_activity_id',
          'sync_blocked_reason',
        ],
        orderBy: 'id ASC',
      );
      expect(rows, hasLength(2));
      expect(rows.first['id'], blockedId);
      expect(rows.first['synced'], 0);
      expect(rows.first['remote_activity_id'], isNull);
      expect(rows.first['sync_blocked_reason'], 'ACTIVITY_DOMAIN_INVALID');
      expect(rows.last['id'], validId);
      expect(rows.last['synced'], 1);
      expect(rows.last['remote_activity_id'], isNotNull);
      expect(rows.last['sync_blocked_reason'], isNull);
      expect(remoteDataSource.createCalls, 2);
      expect(remoteDataSource.attemptedClientSyncIds, <String>[
        'permanent-invalid',
        'valid-after-block',
      ]);

      await repository.syncWorkouts();
      expect(remoteDataSource.createCalls, 2);
    },
  );

  test('retryable 429 leaves the workout eligible for a later sync', () async {
    const userId = 7;
    const clientSyncId = 'retry-after-admission';
    final service = await harness.openService();
    final remoteDataSource =
        _BlockingActivityRemoteDataSource()
          ..createErrorsByClientSyncId[clientSyncId] =
              const HttpStatusException(
                429,
                'Another activity request is already in progress',
                code: 'ACTIVITY_REQUEST_BUSY',
                retryable: true,
              );
    final repository = WorkoutRepositoryImpl(
      WorkoutLocalDataSource(service),
      _FakeAuthRepository(userId),
      remoteDataSource,
    );
    final localWorkoutId = await service.saveWorkoutInLocalDatabase(
      _completedWorkout(clientSyncId: clientSyncId, userId: userId),
      userId: userId,
    );

    await repository.syncWorkouts();

    var rows = await (await service.database).query(
      'workouts',
      columns: <String>['synced', 'sync_blocked_reason'],
      where: 'id = ?',
      whereArgs: <Object?>[localWorkoutId],
    );
    expect(rows.single['synced'], 0);
    expect(rows.single['sync_blocked_reason'], isNull);
    expect(remoteDataSource.createCalls, 1);

    remoteDataSource.createErrorsByClientSyncId.remove(clientSyncId);
    await repository.syncWorkouts();

    rows = await (await service.database).query(
      'workouts',
      columns: <String>['synced', 'sync_blocked_reason'],
      where: 'id = ?',
      whereArgs: <Object?>[localWorkoutId],
    );
    expect(rows.single['synced'], 1);
    expect(rows.single['sync_blocked_reason'], isNull);
    expect(remoteDataSource.createCalls, 2);
  });

  test(
    'owner change during permanent rejection halts before the next owned row',
    () async {
      const userA = 7;
      const userB = 8;
      const clientSyncId = 'rejection-owner-race';
      final service = await harness.openService();
      final remoteDataSource =
          _BlockingActivityRemoteDataSource()
            ..createErrorsByClientSyncId[clientSyncId] =
                const HttpStatusException(
                  413,
                  'Activity payload is too large',
                  code: 'ACTIVITY_PAYLOAD_TOO_LARGE',
                  retryable: false,
                );
      final authRepository = _FakeAuthRepository(userA);
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        authRepository,
        remoteDataSource,
      );
      final localWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: clientSyncId, userId: userA),
        userId: userA,
      );
      await service.saveWorkoutInLocalDatabase(
        _completedWorkout(
          clientSyncId: 'rejection-owner-race-next',
          userId: userA,
        ),
        userId: userA,
      );
      final reachedRemote = Completer<void>();
      final allowRemote = Completer<void>();
      remoteDataSource
        ..reachedRemote = reachedRemote
        ..allowRemote = allowRemote;

      final sync = repository.syncWorkouts();
      await reachedRemote.future;
      authRepository.currentUserId = userB;
      allowRemote.complete();
      await sync;

      final rows = await (await service.database).query(
        'workouts',
        columns: <String>['synced', 'sync_blocked_reason'],
        where: 'id = ?',
        whereArgs: <Object?>[localWorkoutId],
      );
      expect(rows.single['synced'], 0);
      expect(rows.single['sync_blocked_reason'], isNull);
      expect(remoteDataSource.createCalls, 1);
      expect(remoteDataSource.attemptedClientSyncIds, <String>[clientSyncId]);
      expect(
        await service.getUnsyncedWorkoutsFromLocalDatabase(userA),
        hasLength(2),
      );
    },
  );

  test(
    'migrated duplicate client identity permits at most one remote create',
    () async {
      const userId = 7;
      final legacyDatabase = await harness.createLegacyDatabase(
        LegacyDatabaseVariant.version5,
      );
      await legacyDatabase.insert(
        'workouts',
        _legacyWorkoutRow(id: 1, userId: userId),
      );
      await legacyDatabase.insert(
        'workouts',
        _legacyWorkoutRow(id: 2, userId: userId),
      );
      await legacyDatabase.close();

      final service = await harness.openService();
      final remoteDataSource = _BlockingActivityRemoteDataSource();
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        _FakeAuthRepository(userId),
        remoteDataSource,
      );

      await repository.syncWorkouts();

      expect(remoteDataSource.createCalls, 1);
      expect(
        await service.getUnsyncedWorkoutsFromLocalDatabase(userId),
        isEmpty,
      );
      final rows = await (await service.database).query(
        'workouts',
        columns: <String>['synced', 'sync_blocked_reason'],
        orderBy: 'id ASC',
      );
      expect(rows, hasLength(2));
      expect(rows.first['synced'], 1);
      expect(rows.first['sync_blocked_reason'], isNull);
      expect(rows.last['synced'], 0);
      expect(rows.last['sync_blocked_reason'], 'duplicate_client_sync_id');
    },
  );

  for (final rejection in <(String, int, String?, String)>[
    (
      'known-code-400',
      400,
      'ACTIVITY_REQUEST_INVALID',
      'ACTIVITY_REQUEST_INVALID',
    ),
    ('proxy-413', 413, null, 'ACTIVITY_HTTP_413'),
    (
      'known-code-422',
      422,
      'ACTIVITY_DOMAIN_INVALID',
      'ACTIVITY_DOMAIN_INVALID',
    ),
    (
      'unknown-code-422',
      422,
      'raw-details-that-must-not-be-persisted',
      'ACTIVITY_HTTP_422',
    ),
  ]) {
    test('${rejection.$1} permanently blocks activity create', () async {
      const userId = 7;
      final clientSyncId = 'permanent-${rejection.$1}';
      final service = await harness.openService();
      final remoteDataSource =
          _BlockingActivityRemoteDataSource()
            ..createErrorsByClientSyncId[clientSyncId] = HttpStatusException(
              rejection.$2,
              'Permanent activity rejection',
              code: rejection.$3,
              retryable: false,
            );
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        _FakeAuthRepository(userId),
        remoteDataSource,
      );
      final localWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: clientSyncId, userId: userId),
        userId: userId,
      );

      await repository.syncWorkouts();

      final rows = await (await service.database).query(
        'workouts',
        columns: <String>['synced', 'sync_blocked_reason'],
        where: 'id = ?',
        whereArgs: <Object?>[localWorkoutId],
      );
      expect(rows.single['synced'], 0);
      expect(rows.single['sync_blocked_reason'], rejection.$4);
      expect(
        await service.getUnsyncedWorkoutsFromLocalDatabase(userId),
        isEmpty,
      );
    });
  }

  for (final failure in <(String, Object)>[
    ('401', UnauthorizedException('expired')),
    ('403', ForbiddenException('forbidden')),
    (
      '429',
      const HttpStatusException(
        429,
        'Busy',
        code: 'ACTIVITY_REQUEST_BUSY',
        retryable: true,
      ),
    ),
    ('500', ServerException('unavailable')),
    ('network', NetworkException('offline')),
  ]) {
    test('${failure.$1} activity create failure remains retryable', () async {
      const userId = 7;
      final clientSyncId = 'retryable-${failure.$1}';
      final service = await harness.openService();
      final remoteDataSource =
          _BlockingActivityRemoteDataSource()
            ..createErrorsByClientSyncId[clientSyncId] = failure.$2;
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        _FakeAuthRepository(userId),
        remoteDataSource,
      );
      final localWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(clientSyncId: clientSyncId, userId: userId),
        userId: userId,
      );

      await repository.syncWorkouts();

      final rows = await (await service.database).query(
        'workouts',
        columns: <String>['synced', 'sync_blocked_reason'],
        where: 'id = ?',
        whereArgs: <Object?>[localWorkoutId],
      );
      expect(rows.single['synced'], 0);
      expect(rows.single['sync_blocked_reason'], isNull);
      expect(
        await service.getUnsyncedWorkoutsFromLocalDatabase(userId),
        hasLength(1),
      );
    });
  }

  test(
    'unhandled remote auth failure leaves a claimed delete retryable',
    () async {
      const userId = 7;
      final service = await harness.openService();
      final remoteDataSource =
          _BlockingActivityRemoteDataSource()..unauthorizedFirstDelete = true;
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        _FakeAuthRepository(userId),
        remoteDataSource,
      );
      final localWorkoutId = await service.saveWorkoutInLocalDatabase(
        _completedWorkout(
          clientSyncId: 'delete-auth-retry',
          userId: userId,
          remoteActivityId: 701,
        ),
        userId: userId,
      );
      await service.deleteWorkoutFromLocalDatabase(
        localWorkoutId,
        userId: userId,
      );

      await repository.syncWorkouts();

      expect(remoteDataSource.deleteCalls, 1);
      final database = await service.database;
      expect(
        await database.query(
          'workouts',
          where: 'id = ?',
          whereArgs: <Object?>[localWorkoutId],
        ),
        hasLength(1),
      );
      final queue = await database.query('workout_delete_queue');
      expect(queue, hasLength(1));
      expect(queue.single['status'], 'retrying');
      expect(queue.single['retry_count'], 1);
    },
  );
}

WorkoutSessionEntity _completedWorkout({
  required String clientSyncId,
  required int userId,
  int? remoteActivityId,
}) {
  return WorkoutSessionEntity(
    clientSyncId: clientSyncId,
    remoteActivityId: remoteActivityId,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: DateTime.utc(2026, 7, 11, 10),
    endTime: DateTime.utc(2026, 7, 11, 11),
    totalDistance: 10000,
    userId: userId,
  );
}

Map<String, Object?> _legacyWorkoutRow({required int id, required int userId}) {
  return <String, Object?>{
    'id': id,
    'type': 'running',
    'status': 'completed',
    'start_time': '2026-07-11T10:00:00.000Z',
    'end_time': '2026-07-11T11:00:00.000Z',
    'paused_duration': 0,
    'metrics_version': 2,
    'total_distance': 10000.0,
    'average_speed': 10000 / 3600,
    'max_speed': 4.0,
    'average_pace': 6.0,
    'calories': 500,
    'elevation_gain': 0.0,
    'elevation_loss': 0.0,
    'user_id': userId,
    'name': 'duplicate-$id',
    'notes': null,
    'remote_activity_id': null,
    'client_sync_id': 'lost-response-identity',
    'deleted_locally': 0,
    'synced': 0,
  };
}

Future<void> _pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _BlockingActivityRemoteDataSource implements ActivityRemoteDataSource {
  Completer<void>? reachedRemote;
  Completer<void>? allowRemote;
  int createCalls = 0;
  int deleteCalls = 0;
  bool unauthorizedFirstDelete = false;
  final List<String> attemptedClientSyncIds = <String>[];
  final List<int> deletedActivityIds = <int>[];
  final Map<String, Object> createErrorsByClientSyncId = <String, Object>{};

  @override
  Future<int> createActivity(Map<String, dynamic> activityJson) async {
    final clientSyncId = activityJson['clientSyncId']! as String;
    attemptedClientSyncIds.add(clientSyncId);
    createCalls += 1;
    final reached = reachedRemote;
    if (reached != null && !reached.isCompleted) {
      reached.complete();
    }
    final allow = allowRemote;
    if (allow != null) {
      await allow.future;
    }
    final createError = createErrorsByClientSyncId[clientSyncId];
    if (createError != null) {
      throw createError;
    }
    return 1000 + createCalls;
  }

  @override
  Future<void> deleteActivity(int activityId) async {
    deleteCalls += 1;
    deletedActivityIds.add(activityId);
    if (unauthorizedFirstDelete && deleteCalls == 1) {
      throw UnauthorizedException('expired');
    }
  }

  @override
  Future<Map<String, dynamic>> fetchActivities({
    int page = 1,
    int limit = 50,
  }) async {
    return <String, dynamic>{
      'activities': <dynamic>[],
      'pagination': <String, dynamic>{'hasNextPage': false},
    };
  }
}

class _ExitLiveTrackingRepository implements LiveTrackingRepository {
  DateTime currentTime;

  _ExitLiveTrackingRepository(this.currentTime);

  @override
  Stream<TrackingPointEntity> get locationStream => const Stream.empty();

  @override
  DateTime now() => currentTime;

  @override
  Future<LocationServiceStatus> checkPermissions() async {
    return LocationServiceStatus.granted;
  }

  @override
  Future<void> startTracking() async {}

  @override
  Future<void> stopTracking() async {}

  @override
  Future<TrackingPointEntity?> getCurrentLocation() async => null;

  @override
  double calculateDistance(
    TrackingPointEntity point1,
    TrackingPointEntity point2,
  ) {
    return 0;
  }

  @override
  Future<double?> getCurrentElevation() async => null;

  @override
  Future<bool> requestLocationService() async => true;
}

class _NoopTimer implements Timer {
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _isActive = false;
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<UserEntity> refreshCurrentUser() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

  int? currentUserId;
  final List<int> historyResetUserIds = <int>[];

  _FakeAuthRepository(this.currentUserId);

  UserEntity? get _user {
    final userId = currentUserId;
    return userId == null
        ? null
        : UserEntity(
          id: '$userId',
          firstName: 'Test',
          lastName: 'User',
          email: 'test@example.com',
        );
  }

  @override
  Future<UserEntity?> getCurrentUser() async => _user;

  @override
  Future<UserEntity> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updateCurrentUser(UserEntity user) async {
    currentUserId = int.parse(user.id);
  }

  @override
  Future<UserEntity> refreshToken() async => _user!;

  @override
  Future<UserEntity> login(LoginRequestEntity request) {
    throw UnimplementedError();
  }

  @override
  Future<UserEntity?> loginWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() {
    throw UnimplementedError();
  }

  @override
  Future<void> signOutFromGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasOfflineAccess() {
    throw UnimplementedError();
  }

  @override
  Future<bool> needsTokenRefresh() {
    throw UnimplementedError();
  }

  @override
  Future<SessionValidationStatus> validateSession() {
    throw UnimplementedError();
  }

  @override
  Future<void> clearAuthData() {
    throw UnimplementedError();
  }

  @override
  Future<void> markAuthCleanupPending() {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasPendingAuthCleanup() {
    throw UnimplementedError();
  }

  @override
  Future<bool> canStayLoggedInOffline() {
    throw UnimplementedError();
  }

  @override
  Future<bool> needsBackendSync() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateLastBackendSync() {
    throw UnimplementedError();
  }

  @override
  Future<bool> isHistoryRestored(String userId) async => false;

  @override
  Future<void> setHistoryRestored(String userId, bool value) async {
    if (!value) historyResetUserIds.add(int.parse(userId));
  }
}
