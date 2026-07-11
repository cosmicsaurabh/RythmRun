import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
}

WorkoutSessionEntity _completedWorkout({
  required String clientSyncId,
  required int userId,
}) {
  return WorkoutSessionEntity(
    clientSyncId: clientSyncId,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: DateTime.utc(2026, 7, 11, 10),
    endTime: DateTime.utc(2026, 7, 11, 11),
    totalDistance: 10000,
    userId: userId,
  );
}

Future<void> _pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _BlockingActivityRemoteDataSource implements ActivityRemoteDataSource {
  Completer<void>? reachedRemote;
  Completer<void>? allowRemote;
  int createCalls = 0;

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
  ) async {}
}

class _FakeAuthLocalDataSource extends AuthLocalDataSource {
  @override
  Future<Map<String, String>?> getAuthHeaders() async {
    return const <String, String>{'Authorization': 'Bearer test'};
  }
}

class _FakeAuthRepository implements AuthRepository {
  final UserEntity _user;

  _FakeAuthRepository(int userId)
    : _user = UserEntity(
        id: '$userId',
        firstName: 'Test',
        lastName: 'User',
        email: 'test@example.com',
      );

  @override
  Future<UserEntity?> getCurrentUser() async => _user;

  @override
  Future<UserEntity> refreshToken() async => _user;

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
