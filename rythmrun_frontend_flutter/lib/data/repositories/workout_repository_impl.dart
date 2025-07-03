import 'dart:developer';

import 'package:rythmrun_frontend_flutter/const/ensure_type_helper.dart';

import '../../domain/repositories/workout_repository.dart';
import '../../domain/entities/workout_session_entity.dart';
import '../datasources/workout_local_datasource.dart';
import '../../domain/repositories/auth_repository.dart';

class WorkoutRepositoryImpl implements WorkoutRepository {
  final WorkoutLocalDataSource _localDataSource;
  final AuthRepository _authRepository;

  WorkoutRepositoryImpl(this._localDataSource, this._authRepository);

  /// Get current user ID from auth repository
  Future<int?> _getCurrentUserId() async {
    final user = await _authRepository.getCurrentUser();
    return user?.id != null ? EnsureTypeHelper.ensureInt(user!.id) : null;
  }

  @override
  Future<int> saveWorkout(WorkoutSessionEntity workout) async {
    try {
      // Save to local database
      final workoutId = await _localDataSource.saveWorkoutInLocalDatabase(
        workout,
      );

      // TODO: Try to sync with server (fire and forget)
      // Don't wait for sync to complete
      syncWorkouts().catchError((e) {
        log('Failed to sync workout: $e');
      });

      return workoutId;
    } catch (e) {
      throw Exception('Failed to save workout: $e');
    }
  }

  @override
  Future<List<WorkoutSessionEntity>> getWorkouts() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      return await _localDataSource.getWorkoutsFromLocalDatabase(userId);
    } catch (e) {
      throw Exception('Failed to get workouts: $e');
    }
  }

  @override
  Future<WorkoutSessionEntity?> getWorkout(int workoutId) async {
    try {
      return await _localDataSource.getWorkoutFromLocalDatabase(workoutId);
    } catch (e) {
      throw Exception('Failed to get workout: $e');
    }
  }

  @override
  Future<void> deleteWorkout(int workoutId) async {
    try {
      await _localDataSource.deleteWorkoutFromLocalDatabase(workoutId);
    } catch (e) {
      throw Exception('Failed to delete workout: $e');
    }
  }

  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedWorkouts() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      return await _localDataSource.getUnsyncedWorkoutsFromLocalDatabase(
        userId,
      );
    } catch (e) {
      throw Exception('Failed to get unsynced workouts: $e');
    }
  }

  @override
  Future<void> markWorkoutAsSynced(int workoutId) async {
    try {
      await _localDataSource.markWorkoutAsSyncedInLocalDatabase(workoutId);
    } catch (e) {
      throw Exception('Failed to mark workout as synced: $e');
    }
  }

  @override
  Future<void> syncWorkouts() async {
    // TODO: Implement server sync
    // For now, this is a placeholder
    // 1. Get unsynced workouts
    // 2. Send to server
    // 3. Mark as synced on success
    log('Workout sync not implemented yet');
  }
}
