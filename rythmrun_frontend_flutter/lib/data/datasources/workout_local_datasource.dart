import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class WorkoutLocalDataSource {
  final LocalDbService _localDbService;

  WorkoutLocalDataSource(this._localDbService);

  Future<int> saveWorkoutInLocalDatabase(WorkoutSessionEntity workout) async {
    return await _localDbService.saveWorkoutInLocalDatabase(workout);
  }

  Future<List<WorkoutSessionEntity>> getWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    return await _localDbService.getWorkoutsFromLocalDatabase(userId);
  }

  Future<WorkoutSessionEntity?> getWorkoutFromLocalDatabase(
    int workoutId,
  ) async {
    return await _localDbService.getWorkoutFromLocalDatabase(workoutId);
  }

  Future<void> deleteWorkoutFromLocalDatabase(int workoutId) async {
    await _localDbService.deleteWorkoutFromLocalDatabase(workoutId);
  }

  Future<List<WorkoutSessionEntity>> getUnsyncedWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    return await _localDbService.getUnsyncedWorkoutsFromLocalDatabase(userId);
  }

  Future<void> markWorkoutAsSyncedInLocalDatabase(int workoutId) async {
    await _localDbService.markWorkoutAsSyncedInLocalDatabase(workoutId);
  }

  Future<void> clearAllDataFromLocalDatabase() async {
    await _localDbService.clearAllDataFromLocalDatabase();
  }

  // ==================== NEW PAGINATION & STATS METHODS ====================

  /// Get workout statistics using SQL aggregation
  Future<WorkoutStatistics> getWorkoutStatistics(
    int userId, {
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _localDbService.getWorkoutStatistics(
      userId,
      workoutType: workoutType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Get workout statistics grouped by type
  Future<Map<String, WorkoutStatistics>> getWorkoutStatisticsByType(
    int userId,
  ) async {
    return await _localDbService.getWorkoutStatisticsByType(userId);
  }

  /// Get paginated workouts with filtering
  Future<PaginatedWorkouts> getPaginatedWorkouts(
    int userId, {
    int page = 1,
    int limit = 20,
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    bool loadTrackingPoints = false,
  }) async {
    return await _localDbService.getPaginatedWorkouts(
      userId,
      page: page,
      limit: limit,
      workoutType: workoutType,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
      loadTrackingPoints: loadTrackingPoints,
    );
  }

  /// Get workout count for quick stats
  Future<int> getWorkoutCount(int userId) async {
    return await _localDbService.getWorkoutCount(userId);
  }
}
