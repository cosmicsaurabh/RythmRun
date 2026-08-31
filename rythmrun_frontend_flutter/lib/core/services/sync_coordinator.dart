import 'dart:async';

import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';

class SyncCoordinator {
  final WorkoutRepository _workoutRepository;
  final ActivityImageRepository _activityImageRepository;
  final AuthRepository _authRepository;
  final UserScopeOperationGate _operationGate;
  final OnlineOperationGuard? _onlineOperationGuard;
  final void Function()? onRestoreStart;
  final void Function()? onRestoreComplete;
  final void Function()? onRestoreFailed;
  Future<void>? _activeSync;
  int? _activeSyncOwnerId;
  bool _followUpRequested = false;

  SyncCoordinator({
    required WorkoutRepository workoutRepository,
    required ActivityImageRepository activityImageRepository,
    required AuthRepository authRepository,
    required UserScopeOperationGate operationGate,
    OnlineOperationGuard? onlineOperationGuard,
    this.onRestoreStart,
    this.onRestoreComplete,
    this.onRestoreFailed,
  }) : _workoutRepository = workoutRepository,
       _activityImageRepository = activityImageRepository,
       _authRepository = authRepository,
       _operationGate = operationGate,
       _onlineOperationGuard = onlineOperationGuard;

  Future<void> syncAll() async {
    // Background sync is a server mutation; deny it while offline. The session
    // coordinator keeps this guard aligned with session state (IP-2.3).
    final guard = _onlineOperationGuard;
    if (guard != null && !guard.isOnline) {
      return;
    }

    final initialUser = await _authRepository.getCurrentUser();
    final userId = int.tryParse(initialUser?.id ?? '');
    if (userId == null || userId <= 0) {
      return;
    }

    final activeSync = _activeSync;
    if (activeSync != null) {
      if (_activeSyncOwnerId == userId &&
          !_operationGate.isSuspended &&
          _operationGate.activeUserId == userId) {
        _followUpRequested = true;
      }
      await activeSync;
      return;
    }

    final completion = Completer<void>();
    _activeSyncOwnerId = userId;
    _followUpRequested = false;
    _activeSync = completion.future;

    unawaited(
      _runSyncFlight(userId).then<void>(
        (_) {
          _clearActiveSync();
          completion.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          _clearActiveSync();
          completion.completeError(error, stackTrace);
        },
      ),
    );

    await completion.future;
  }

  Future<void> _runSyncFlight(int userId) async {
    final operationLease = _operationGate.tryAcquire(userId);
    if (operationLease == null) {
      return;
    }

    try {
      await _runSyncPass(userId);

      if (!_followUpRequested ||
          (_onlineOperationGuard != null && !_onlineOperationGuard.isOnline) ||
          !await _isActiveOwner(userId)) {
        return;
      }

      _followUpRequested = false;
      await _runSyncPass(userId);
    } finally {
      operationLease.release();
    }
  }

  Future<void> _runSyncPass(int userId) async {
    if (!await _isActiveOwner(userId)) {
      return;
    }

    await _restoreHistory(userId);

    if (!await _isActiveOwner(userId)) {
      return;
    }
    await _workoutRepository.syncWorkouts();

    if (!await _isActiveOwner(userId)) {
      return;
    }

    await _activityImageRepository.syncPendingImages();
  }

  void _clearActiveSync() {
    _activeSync = null;
    _activeSyncOwnerId = null;
    _followUpRequested = false;
  }

  Future<void> _restoreHistory(int userId) async {
    try {
      final isRestored = await _workoutRepository.isHistoryRestored(userId);
      if (isRestored) {
        return;
      }

      onRestoreStart?.call();
      await _workoutRepository.downloadAndRestoreWorkouts();
      if (!await _isActiveOwner(userId)) {
        onRestoreFailed?.call();
        return;
      }

      await _workoutRepository.setHistoryRestored(userId, true);
      if (!await _isActiveOwner(userId)) {
        onRestoreFailed?.call();
        return;
      }

      onRestoreComplete?.call();
    } catch (_) {
      onRestoreFailed?.call();
    }
  }

  Future<bool> _isActiveOwner(int userId) async {
    if (_operationGate.isSuspended || _operationGate.activeUserId != userId) {
      return false;
    }

    final currentUser = await _authRepository.getCurrentUser();
    return int.tryParse(currentUser?.id ?? '') == userId;
  }
}
