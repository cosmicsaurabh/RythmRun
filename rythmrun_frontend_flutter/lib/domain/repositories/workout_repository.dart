import '../entities/workout_session_entity.dart';

abstract class WorkoutRepository {
  /// Save a completed workout
  Future<int> saveWorkout(WorkoutSessionEntity workout);

  /// Get all workouts for the current user
  Future<List<WorkoutSessionEntity>> getWorkouts();

  /// Get a single workout by ID
  Future<WorkoutSessionEntity?> getWorkout(int workoutId);

  /// Delete a workout
  Future<void> deleteWorkout(int workoutId);

  /// Get unsynced workouts for syncing to server
  Future<List<WorkoutSessionEntity>> getUnsyncedWorkouts();

  /// Mark workout as synced
  Future<void> markWorkoutAsSynced(int workoutId);

  /// Sync workouts with server
  Future<void> syncWorkouts();
}
