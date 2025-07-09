import '../entities/workout_session_entity.dart';
import '../../core/services/local_db_service.dart';

abstract class WorkoutRepository {
  /// Save a completed workout
  Future<int> saveWorkout(WorkoutSessionEntity workout);

  /// Get all workouts for the current user
  Future<List<WorkoutSessionEntity>> getWorkouts();

  /// Get a single workout by ID
  Future<WorkoutSessionEntity?> getWorkout(int workoutId);

  /// Check if user has local access (authenticated or offline mode)
  Future<bool> hasLocalAccess();

  /// Delete a workout
  Future<void> deleteWorkout(int workoutId);

  /// Get unsynced workouts for syncing to server
  Future<List<WorkoutSessionEntity>> getUnsyncedWorkouts();

  /// Mark workout as synced
  Future<void> markWorkoutAsSynced(int workoutId);

  /// Sync workouts with server
  Future<void> syncWorkouts();

  // ==================== NEW PAGINATION & STATS METHODS ====================

  /// Get workout statistics using SQL aggregation
  Future<WorkoutStatistics> getWorkoutStatistics({
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get workout statistics grouped by type
  Future<Map<String, WorkoutStatistics>> getWorkoutStatisticsByType();

  /// Get paginated workouts with filtering
  Future<PaginatedWorkouts> getPaginatedWorkouts({
    int page = 1,
    int limit = 20,
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    bool loadTrackingPoints = false,
  });

  /// Get workout count for quick stats
  Future<int> getWorkoutCount();
}
