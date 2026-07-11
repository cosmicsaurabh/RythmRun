import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class WorkoutLocalDataSource {
  final LocalDbService _localDbService;

  WorkoutLocalDataSource(this._localDbService);

  Future<int> saveWorkoutInLocalDatabase(
    WorkoutSessionEntity workout, {
    required int userId,
  }) async {
    return await _localDbService.saveWorkoutInLocalDatabase(
      workout,
      userId: userId,
    );
  }

  Future<List<WorkoutSessionEntity>> getWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    return await _localDbService.getWorkoutsFromLocalDatabase(userId);
  }

  Future<WorkoutSessionEntity?> getWorkoutFromLocalDatabase(
    int workoutId, {
    required int userId,
  }) async {
    return await _localDbService.getWorkoutFromLocalDatabase(
      workoutId,
      userId: userId,
    );
  }

  Future<void> deleteWorkoutFromLocalDatabase(
    int workoutId, {
    required int userId,
  }) async {
    await _localDbService.deleteWorkoutFromLocalDatabase(
      workoutId,
      userId: userId,
    );
  }

  Future<List<WorkoutSessionEntity>> getUnsyncedWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    return await _localDbService.getUnsyncedWorkoutsFromLocalDatabase(userId);
  }

  Future<void> markWorkoutAsSyncedInLocalDatabase(
    int workoutId, {
    required int userId,
  }) async {
    await _localDbService.markWorkoutAsSyncedInLocalDatabase(
      workoutId,
      userId: userId,
    );
  }

  Future<void> updateRemoteActivityId(
    int localId,
    int remoteId, {
    required int userId,
  }) async {
    await _localDbService.updateRemoteActivityId(
      localId,
      remoteId,
      userId: userId,
    );
  }

  Future<bool> recordWorkoutSyncSuccess({
    required int userId,
    required int localWorkoutId,
    required String clientSyncId,
    required int remoteActivityId,
  }) {
    return _localDbService.recordWorkoutSyncSuccess(
      userId: userId,
      localWorkoutId: localWorkoutId,
      clientSyncId: clientSyncId,
      remoteActivityId: remoteActivityId,
    );
  }

  Future<List<WorkoutDeleteQueueEntry>> getWorkoutDeletesReadyForSync(
    int userId,
    DateTime now,
  ) async {
    return await _localDbService.getWorkoutDeletesReadyForSync(userId, now);
  }

  Future<bool> markWorkoutDeleteDeleting(int queueId, {required int userId}) {
    return _localDbService.markWorkoutDeleteDeleting(queueId, userId: userId);
  }

  Future<void> markWorkoutDeleteRetrying({
    required int queueId,
    required int userId,
    required int retryCount,
    required String error,
    required DateTime nextRetryAt,
  }) async {
    await _localDbService.markWorkoutDeleteRetrying(
      queueId: queueId,
      userId: userId,
      retryCount: retryCount,
      error: error,
      nextRetryAt: nextRetryAt,
    );
  }

  Future<void> completeWorkoutDelete({
    required int queueId,
    required int localWorkoutId,
    required int userId,
  }) async {
    await _localDbService.completeWorkoutDelete(
      queueId: queueId,
      localWorkoutId: localWorkoutId,
      userId: userId,
    );
  }

  Future<void> resetStaleWorkoutDeletes(
    int userId,
    DateTime staleBefore,
  ) async {
    await _localDbService.resetStaleWorkoutDeletes(userId, staleBefore);
  }

  Future<void> ensureClientSyncIds(int userId) async {
    await _localDbService.ensureClientSyncIds(userId);
  }

  Future<void> clearUserDataFromLocalDatabase(int userId) async {
    await _localDbService.clearUserDataFromLocalDatabase(userId);
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
