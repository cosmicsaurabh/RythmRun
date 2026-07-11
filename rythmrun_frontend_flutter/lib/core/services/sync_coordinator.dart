import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';

class SyncCoordinator {
  final WorkoutRepository _workoutRepository;
  final ActivityImageRepository _activityImageRepository;
  final AuthRepository _authRepository;
  final UserScopeOperationGate _operationGate;

  SyncCoordinator({
    required WorkoutRepository workoutRepository,
    required ActivityImageRepository activityImageRepository,
    required AuthRepository authRepository,
    required UserScopeOperationGate operationGate,
  }) : _workoutRepository = workoutRepository,
       _activityImageRepository = activityImageRepository,
       _authRepository = authRepository,
       _operationGate = operationGate;

  Future<void> syncAll() async {
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
      await _workoutRepository.syncWorkouts();

      final currentUser = await _authRepository.getCurrentUser();
      final currentUserId = int.tryParse(currentUser?.id ?? '');
      if (currentUserId != userId ||
          _operationGate.isSuspended ||
          _operationGate.activeUserId != userId) {
        return;
      }

      await _activityImageRepository.syncPendingImages();
    } finally {
      operationLease.release();
    }
  }
}
