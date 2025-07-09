import 'dart:developer';

import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/ensure_type_helper.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/workout_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';

class WorkoutRepositoryImpl implements WorkoutRepository {
  final WorkoutLocalDataSource _localDataSource;
  final AuthRepository _authRepository;

  WorkoutRepositoryImpl(this._localDataSource, this._authRepository);

  /// Get current user ID from auth repository
  /// Returns null only if no user data is available locally
  @override
  Future<int?> getCurrentUserId() async {
    final user = await _authRepository.getCurrentUser();
    return user?.id != null ? EnsureTypeHelper.ensureInt(user!.id) : null;
  }

  /// Check if user has local access (authenticated or offline mode)
  @override
  Future<bool> hasLocalAccess() async {
    final userId = await getCurrentUserId();
    return userId != null;
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
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception(
          'No user data available - please sign in to access workouts',
        );
      }

      // This works offline since it's reading from local database
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
      final userId = await getCurrentUserId();
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

  // ==================== NEW PAGINATION & STATS METHODS ====================

  @override
  Future<WorkoutStatistics> getWorkoutStatistics({
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      return await _localDataSource.getWorkoutStatistics(
        userId,
        workoutType: workoutType,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      throw Exception('Failed to get workout statistics: $e');
    }
  }

  @override
  Future<Map<String, WorkoutStatistics>> getWorkoutStatisticsByType() async {
    try {
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      return await _localDataSource.getWorkoutStatisticsByType(userId);
    } catch (e) {
      throw Exception('Failed to get workout statistics by type: $e');
    }
  }

  @override
  Future<PaginatedWorkouts> getPaginatedWorkouts({
    int page = 1,
    int limit = 20,
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    bool loadTrackingPoints = false,
  }) async {
    try {
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      return await _localDataSource.getPaginatedWorkouts(
        userId,
        page: page,
        limit: limit,
        workoutType: workoutType,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        loadTrackingPoints: loadTrackingPoints,
      );
    } catch (e) {
      throw Exception('Failed to get paginated workouts: $e');
    }
  }

  @override
  Future<int> getWorkoutCount() async {
    try {
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      return await _localDataSource.getWorkoutCount(userId);
    } catch (e) {
      throw Exception('Failed to get workout count: $e');
    }
  }
}
