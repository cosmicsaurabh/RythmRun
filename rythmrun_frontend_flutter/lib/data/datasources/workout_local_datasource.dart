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
}
