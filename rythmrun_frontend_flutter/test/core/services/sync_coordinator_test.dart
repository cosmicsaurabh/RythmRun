import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/sync_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';

void main() {
  test('one outer lease covers workout and image synchronization', () async {
    final authRepository = _MutableAuthRepository(7);
    final workoutRepository = _FakeWorkoutRepository();
    final imageRepository = _FakeActivityImageRepository(blockSync: true);
    final operationGate = UserScopeOperationGate()..activate(7);
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: authRepository,
      operationGate: operationGate,
    );

    final sync = coordinator.syncAll();
    await imageRepository.reachedSync.future;

    expect(workoutRepository.syncCalls, 1);
    expect(imageRepository.syncCalls, 1);
    expect(operationGate.activeLeaseCount, 1);

    var didDrain = false;
    final drain = operationGate.suspendAndDrain().then((_) {
      didDrain = true;
    });
    await _pumpMicrotasks();

    expect(didDrain, isFalse);

    imageRepository.allowSync.complete();
    await sync;
    await drain;

    expect(didDrain, isTrue);
    expect(operationGate.activeLeaseCount, 0);
  });

  test('owner change after workout sync prevents image sync', () async {
    final authRepository = _MutableAuthRepository(7);
    final workoutRepository = _FakeWorkoutRepository(
      onSync: () async {
        authRepository.currentUserId = 8;
      },
    );
    final imageRepository = _FakeActivityImageRepository();
    final operationGate = UserScopeOperationGate()..activate(7);
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: authRepository,
      operationGate: operationGate,
    );

    await coordinator.syncAll();

    expect(workoutRepository.syncCalls, 1);
    expect(imageRepository.syncCalls, 0);
    expect(operationGate.activeLeaseCount, 0);
  });

  test('suspended user scope rejects coordinated sync', () async {
    final workoutRepository = _FakeWorkoutRepository();
    final imageRepository = _FakeActivityImageRepository();
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: _MutableAuthRepository(7),
      operationGate: UserScopeOperationGate(),
    );

    await coordinator.syncAll();

    expect(workoutRepository.syncCalls, 0);
    expect(imageRepository.syncCalls, 0);
  });
}

Future<void> _pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeWorkoutRepository implements WorkoutRepository {
  final Future<void> Function()? onSync;
  int syncCalls = 0;

  _FakeWorkoutRepository({this.onSync});

  @override
  Future<void> syncWorkouts() async {
    syncCalls += 1;
    await onSync?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeActivityImageRepository implements ActivityImageRepository {
  final bool blockSync;
  final Completer<void> reachedSync = Completer<void>();
  final Completer<void> allowSync = Completer<void>();
  int syncCalls = 0;

  _FakeActivityImageRepository({this.blockSync = false});

  @override
  Future<void> syncPendingImages() async {
    syncCalls += 1;
    if (!reachedSync.isCompleted) {
      reachedSync.complete();
    }
    if (blockSync) {
      await allowSync.future;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableAuthRepository implements AuthRepository {
  int? currentUserId;

  _MutableAuthRepository(this.currentUserId);

  @override
  Future<UserEntity?> getCurrentUser() async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    return UserEntity(
      id: '$userId',
      firstName: 'User',
      lastName: '$userId',
      email: 'user$userId@example.com',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
