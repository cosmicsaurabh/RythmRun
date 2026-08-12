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

    final operationLease = _operationGate.tryAcquire(userId);
    if (operationLease == null) {
      return;
    }

    try {
      final isRestored = await _workoutRepository.isHistoryRestored();
      if (!isRestored) {
        onRestoreStart?.call();
        await _workoutRepository.downloadAndRestoreWorkouts();
        await _workoutRepository.setHistoryRestored(true);
        onRestoreComplete?.call();
      }

      await _workoutRepository.syncWorkouts();

      final currentUser = await _authRepository.getCurrentUser();
      final currentUserId = int.tryParse(currentUser?.id ?? '');
      if (currentUserId != userId ||
          _operationGate.isSuspended ||
          _operationGate.activeUserId != userId) {
        return;
      }

      await _activityImageRepository.syncPendingImages();
    } catch (e) {
      onRestoreFailed?.call();
      rethrow;
    } finally {
      operationLease.release();
    }
  }
}
