import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
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

    final overlappingSync = coordinator.syncAll();
    await _pumpMicrotasks();

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
    await Future.wait(<Future<void>>[sync, overlappingSync]);
    await drain;

    expect(didDrain, isTrue);
    expect(workoutRepository.syncCalls, 1);
    expect(imageRepository.syncCalls, 1);
    expect(operationGate.activeLeaseCount, 0);
  });

  test(
    'overlapping syncAll calls coalesce into one bounded whole-flight follow-up',
    () async {
      final restoreReached = Completer<void>();
      final allowRestore = Completer<void>();
      final followUpWorkoutReached = Completer<void>();
      final allowFollowUpWorkout = Completer<void>();
      late _FakeWorkoutRepository workoutRepository;
      workoutRepository = _FakeWorkoutRepository(
        onDownloadAndRestore: () async {
          restoreReached.complete();
          await allowRestore.future;
        },
        onSync: () async {
          if (workoutRepository.syncCalls == 2) {
            followUpWorkoutReached.complete();
            await allowFollowUpWorkout.future;
          }
        },
      );
      final imageRepository = _FakeActivityImageRepository();
      final operationGate = UserScopeOperationGate()..activate(7);
      var restoreStartCalls = 0;
      var restoreCompleteCalls = 0;
      var restoreFailedCalls = 0;
      final coordinator = SyncCoordinator(
        workoutRepository: workoutRepository,
        activityImageRepository: imageRepository,
        authRepository: _MutableAuthRepository(7),
        operationGate: operationGate,
        onRestoreStart: () => restoreStartCalls += 1,
        onRestoreComplete: () => restoreCompleteCalls += 1,
        onRestoreFailed: () => restoreFailedCalls += 1,
      );

      final firstSync = coordinator.syncAll();
      await restoreReached.future;
      final overlappingSyncs = <Future<void>>[
        coordinator.syncAll(),
        coordinator.syncAll(),
        coordinator.syncAll(),
      ];
      await _pumpMicrotasks();

      expect(workoutRepository.downloadAndRestoreWorkoutsCalls, 1);
      expect(operationGate.activeLeaseCount, 1);

      allowRestore.complete();
      await followUpWorkoutReached.future;
      final requestDuringFollowUp = coordinator.syncAll();
      await _pumpMicrotasks();
      allowFollowUpWorkout.complete();

      await Future.wait(<Future<void>>[
        firstSync,
        ...overlappingSyncs,
        requestDuringFollowUp,
      ]);

      expect(workoutRepository.historyRestoredReadOwnerIds, <int>[7, 7]);
      expect(workoutRepository.downloadAndRestoreWorkoutsCalls, 1);
      expect(workoutRepository.setHistoryRestoredCalls, 1);
      expect(workoutRepository.syncCalls, 2);
      expect(imageRepository.syncCalls, 2);
      expect(restoreStartCalls, 1);
      expect(restoreCompleteCalls, 1);
      expect(restoreFailedCalls, 0);
      expect(operationGate.activeLeaseCount, 0);
    },
  );

  test(
    'overlap from another owner cannot retarget the active restore flight',
    () async {
      final restoreReached = Completer<void>();
      final allowRestore = Completer<void>();
      final authRepository = _MutableAuthRepository(7);
      final workoutRepository = _FakeWorkoutRepository(
        onDownloadAndRestore: () async {
          restoreReached.complete();
          await allowRestore.future;
        },
      );
      final imageRepository = _FakeActivityImageRepository();
      final operationGate = UserScopeOperationGate()..activate(7);
      var restoreCompleteCalls = 0;
      var restoreFailedCalls = 0;
      final coordinator = SyncCoordinator(
        workoutRepository: workoutRepository,
        activityImageRepository: imageRepository,
        authRepository: authRepository,
        operationGate: operationGate,
        onRestoreComplete: () => restoreCompleteCalls += 1,
        onRestoreFailed: () => restoreFailedCalls += 1,
      );

      final firstSync = coordinator.syncAll();
      await restoreReached.future;
      authRepository.currentUserId = 8;
      final otherOwnerSync = coordinator.syncAll();
      await _pumpMicrotasks();
      allowRestore.complete();

      await Future.wait(<Future<void>>[firstSync, otherOwnerSync]);

      expect(workoutRepository.historyRestoredReadOwnerIds, <int>[7]);
      expect(workoutRepository.setHistoryRestoredCalls, 0);
      expect(workoutRepository.syncCalls, 0);
      expect(imageRepository.syncCalls, 0);
      expect(restoreCompleteCalls, 0);
      expect(restoreFailedCalls, 1);
      expect(operationGate.activeLeaseCount, 0);
    },
  );

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

  test('offline mode short-circuits sync before any remote push', () async {
    final workoutRepository = _FakeWorkoutRepository();
    final imageRepository = _FakeActivityImageRepository();
    final guard = OnlineOperationGuard(); // default offline
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: _MutableAuthRepository(7),
      operationGate: UserScopeOperationGate()..activate(7),
      onlineOperationGuard: guard,
    );

    await coordinator.syncAll();
    expect(workoutRepository.syncCalls, 0);
    expect(imageRepository.syncCalls, 0);

    // Once the session is online, coordinated sync proceeds normally.
    guard.setOnline(true);
    await coordinator.syncAll();
    expect(workoutRepository.syncCalls, 1);
    expect(imageRepository.syncCalls, 1);
  });

  test('syncAll triggers restore when history is not restored', () async {
    final authRepository = _MutableAuthRepository(7);
    final workoutRepository = _FakeWorkoutRepository();
    final imageRepository = _FakeActivityImageRepository();
    final operationGate = UserScopeOperationGate()..activate(7);

    var startCalled = false;
    var completeCalled = false;
    var failedCalled = false;

    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: authRepository,
      operationGate: operationGate,
      onRestoreStart: () => startCalled = true,
      onRestoreComplete: () => completeCalled = true,
      onRestoreFailed: () => failedCalled = true,
    );

    expect(workoutRepository.historyRestoredValue, isFalse);

    await coordinator.syncAll();

    expect(workoutRepository.downloadAndRestoreWorkoutsCalls, 1);
    expect(workoutRepository.setHistoryRestoredCalls, 1);
    expect(workoutRepository.historyRestoredReadOwnerIds, <int>[7]);
    expect(workoutRepository.historyRestoredWriteOwnerIds, <int>[7]);
    expect(workoutRepository.historyRestoredValue, isTrue);
    expect(startCalled, isTrue);
    expect(completeCalled, isTrue);
    expect(failedCalled, isFalse);
  });

  test('syncAll skips restore when history is already restored', () async {
    final authRepository = _MutableAuthRepository(7);
    final workoutRepository =
        _FakeWorkoutRepository()..historyRestoredValue = true;
    final imageRepository = _FakeActivityImageRepository();
    final operationGate = UserScopeOperationGate()..activate(7);

    var startCalled = false;
    var completeCalled = false;

    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: authRepository,
      operationGate: operationGate,
      onRestoreStart: () => startCalled = true,
      onRestoreComplete: () => completeCalled = true,
    );

    await coordinator.syncAll();

    expect(workoutRepository.downloadAndRestoreWorkoutsCalls, 0);
    expect(workoutRepository.setHistoryRestoredCalls, 0);
    expect(workoutRepository.historyRestoredReadOwnerIds, <int>[7]);
    expect(workoutRepository.historyRestoredWriteOwnerIds, isEmpty);
    expect(startCalled, isFalse);
    expect(completeCalled, isFalse);
  });

  test(
    'restore failure stays visible while workout and image push run',
    () async {
      final authRepository = _MutableAuthRepository(7);
      final workoutRepository = _FakeWorkoutRepository(
        onDownloadAndRestore: () async {
          throw Exception('Network error');
        },
      );
      final imageRepository = _FakeActivityImageRepository();
      final operationGate = UserScopeOperationGate()..activate(7);

      var startCalled = false;
      var completeCalled = false;
      var failedCalled = false;

      final coordinator = SyncCoordinator(
        workoutRepository: workoutRepository,
        activityImageRepository: imageRepository,
        authRepository: authRepository,
        operationGate: operationGate,
        onRestoreStart: () => startCalled = true,
        onRestoreComplete: () => completeCalled = true,
        onRestoreFailed: () => failedCalled = true,
      );

      await coordinator.syncAll();

      expect(startCalled, isTrue);
      expect(completeCalled, isFalse);
      expect(failedCalled, isTrue);
      expect(workoutRepository.syncCalls, 1);
      expect(imageRepository.syncCalls, 1);
    },
  );

  test('restore flag write failure does not block queued push', () async {
    final workoutRepository = _FakeWorkoutRepository(
      onSetHistoryRestored: () async {
        throw Exception('Preference write failed');
      },
    );
    final imageRepository = _FakeActivityImageRepository();
    var completeCalled = false;
    var failedCalled = false;
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: _MutableAuthRepository(7),
      operationGate: UserScopeOperationGate()..activate(7),
      onRestoreComplete: () => completeCalled = true,
      onRestoreFailed: () => failedCalled = true,
    );

    await coordinator.syncAll();

    expect(workoutRepository.downloadAndRestoreWorkoutsCalls, 1);
    expect(workoutRepository.setHistoryRestoredCalls, 1);
    expect(workoutRepository.historyRestoredValue, isFalse);
    expect(completeCalled, isFalse);
    expect(failedCalled, isTrue);
    expect(workoutRepository.syncCalls, 1);
    expect(imageRepository.syncCalls, 1);
  });

  test('push failure is not reported as a restore failure', () async {
    final workoutRepository = _FakeWorkoutRepository(
      onSync: () async {
        throw Exception('Push failed');
      },
    )..historyRestoredValue = true;
    var failedCalled = false;
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: _FakeActivityImageRepository(),
      authRepository: _MutableAuthRepository(7),
      operationGate: UserScopeOperationGate()..activate(7),
      onRestoreFailed: () => failedCalled = true,
    );

    await expectLater(coordinator.syncAll(), throwsA(isA<Exception>()));

    expect(failedCalled, isFalse);
  });

  test('scope suspension rejects stale restore completion and push', () async {
    final operationGate = UserScopeOperationGate()..activate(7);
    late Future<void> drain;
    final workoutRepository = _FakeWorkoutRepository(
      onDownloadAndRestore: () async {
        drain = operationGate.suspendAndDrain();
      },
    );
    final imageRepository = _FakeActivityImageRepository();
    var completeCalled = false;
    var failedCalled = false;
    final coordinator = SyncCoordinator(
      workoutRepository: workoutRepository,
      activityImageRepository: imageRepository,
      authRepository: _MutableAuthRepository(7),
      operationGate: operationGate,
      onRestoreComplete: () => completeCalled = true,
      onRestoreFailed: () => failedCalled = true,
    );

    await coordinator.syncAll();
    await drain;

    expect(workoutRepository.setHistoryRestoredCalls, 0);
    expect(workoutRepository.historyRestoredValue, isFalse);
    expect(completeCalled, isFalse);
    expect(failedCalled, isTrue);
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
  final Future<void> Function()? onDownloadAndRestore;
  final Future<void> Function()? onSetHistoryRestored;
  int syncCalls = 0;
  bool historyRestoredValue = false;
  int downloadAndRestoreWorkoutsCalls = 0;
  int setHistoryRestoredCalls = 0;
  final List<int> historyRestoredReadOwnerIds = <int>[];
  final List<int> historyRestoredWriteOwnerIds = <int>[];

  _FakeWorkoutRepository({
    this.onSync,
    this.onDownloadAndRestore,
    this.onSetHistoryRestored,
  });

  @override
  Future<void> syncWorkouts() async {
    syncCalls += 1;
    await onSync?.call();
  }

  @override
  Future<bool> isHistoryRestored(int ownerUserId) async {
    historyRestoredReadOwnerIds.add(ownerUserId);
    return historyRestoredValue;
  }

  @override
  Future<void> setHistoryRestored(int ownerUserId, bool value) async {
    setHistoryRestoredCalls++;
    historyRestoredWriteOwnerIds.add(ownerUserId);
    await onSetHistoryRestored?.call();
    historyRestoredValue = value;
  }

  @override
  Future<void> downloadAndRestoreWorkouts() async {
    downloadAndRestoreWorkoutsCalls++;
    await onDownloadAndRestore?.call();
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
  @override
  Future<UserEntity> refreshCurrentUser() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

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
