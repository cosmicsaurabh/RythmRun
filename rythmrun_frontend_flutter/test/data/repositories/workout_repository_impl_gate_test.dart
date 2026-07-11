import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/workout_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/workout_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/registration_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';

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
        _FakeAuthLocalDataSource(),
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
        _FakeAuthLocalDataSource(),
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
        _FakeAuthLocalDataSource(),
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

  test(
    'claimed remote delete retries once after authentication refresh',
    () async {
      const userId = 7;
      final service = await harness.openService();
      final remoteDataSource =
          _BlockingActivityRemoteDataSource()..unauthorizedFirstDelete = true;
      final repository = WorkoutRepositoryImpl(
        WorkoutLocalDataSource(service),
        _FakeAuthRepository(userId),
        remoteDataSource,
        _FakeAuthLocalDataSource(),
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

      expect(remoteDataSource.deleteCalls, 2);
      final database = await service.database;
      expect(
        await database.query(
          'workouts',
          where: 'id = ?',
          whereArgs: <Object?>[localWorkoutId],
        ),
        isEmpty,
      );
      expect(await database.query('workout_delete_queue'), isEmpty);
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

  @override
  Future<int> createActivity(
    Map<String, dynamic> activityJson,
    Map<String, String> authHeaders,
  ) async {
    createCalls += 1;
    final reached = reachedRemote;
    if (reached != null && !reached.isCompleted) {
      reached.complete();
    }
    final allow = allowRemote;
    if (allow != null) {
      await allow.future;
    }
    return 1000 + createCalls;
  }

  @override
  Future<void> deleteActivity(
    int activityId,
    Map<String, String> authHeaders,
  ) async {
    deleteCalls += 1;
    if (unauthorizedFirstDelete && deleteCalls == 1) {
      throw UnauthorizedException('expired');
    }
  }
}

class _FakeAuthLocalDataSource extends AuthLocalDataSource {
  @override
  Future<Map<String, String>?> getAuthHeaders() async {
    return const <String, String>{'Authorization': 'Bearer test'};
  }
}

class _FakeAuthRepository implements AuthRepository {
  int? currentUserId;

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
  Future<UserEntity> refreshToken() async => _user!;

  @override
  Future<UserEntity> login(LoginRequestEntity request) {
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
  Future<void> printStoredData() {
    throw UnimplementedError();
  }
}
