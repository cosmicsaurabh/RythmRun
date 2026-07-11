import 'dart:developer';

import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/core/utils/ensure_type_helper.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/workout_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/activity_sync_model.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';

class WorkoutRepositoryImpl implements WorkoutRepository {
  final WorkoutLocalDataSource _localDataSource;
  final AuthRepository _authRepository;
  final ActivityRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _authLocalDataSource;
  final UserScopeOperationGate? _operationGate;
  bool _isSyncing = false;

  WorkoutRepositoryImpl(
    this._localDataSource,
    this._authRepository,
    this._remoteDataSource,
    this._authLocalDataSource, {
    UserScopeOperationGate? operationGate,
  }) : _operationGate = operationGate;

  /// Get current user ID from auth repository
  /// Returns null only if no user data is available locally
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
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      if (workout.userId != userId) {
        throw StateError('Workout owner does not match the active user');
      }

      // Save to local database
      final workoutId = await _localDataSource.saveWorkoutInLocalDatabase(
        workout,
        userId: userId,
      );

      // Fire-and-forget sync. Local save remains the source of truth.
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
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      return await _localDataSource.getWorkoutFromLocalDatabase(
        workoutId,
        userId: userId,
      );
    } catch (e) {
      throw Exception('Failed to get workout: $e');
    }
  }

  @override
  Future<void> deleteWorkout(int workoutId) async {
    try {
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      await _localDataSource.deleteWorkoutFromLocalDatabase(
        workoutId,
        userId: userId,
      );
      syncWorkouts().catchError((e) {
        log('Failed to sync workout delete: $e');
      });
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
      final userId = await getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      await _localDataSource.markWorkoutAsSyncedInLocalDatabase(
        workoutId,
        userId: userId,
      );
    } catch (e) {
      throw Exception('Failed to mark workout as synced: $e');
    }
  }

  @override
  Future<void> syncWorkouts() async {
    if (_isSyncing) {
      return;
    }

    _isSyncing = true;
    UserScopeOperationLease? operationLease;

    try {
      final userId = await getCurrentUserId();
      if (userId == null) {
        return;
      }

      operationLease = _operationGate?.tryAcquire(userId);
      if (_operationGate != null && operationLease == null) {
        return;
      }

      await _localDataSource.ensureClientSyncIds(userId);

      final initialAuthHeaders = await _authLocalDataSource.getAuthHeaders();
      if (initialAuthHeaders == null) {
        return;
      }
      if (!await _isCurrentUser(userId)) {
        return;
      }
      var authHeaders = initialAuthHeaders;

      await _localDataSource.resetStaleWorkoutDeletes(
        userId,
        DateTime.now().subtract(const Duration(minutes: 15)),
      );

      final deleteSyncAuthHeaders = await _syncPendingWorkoutDeletes(
        userId,
        authHeaders,
      );
      if (deleteSyncAuthHeaders == null) {
        return;
      }
      authHeaders = deleteSyncAuthHeaders;

      final unsyncedWorkouts = await _localDataSource
          .getUnsyncedWorkoutsFromLocalDatabase(userId);

      for (final workout in unsyncedWorkouts) {
        final localWorkoutId = _parseLocalWorkoutId(workout.id);
        if (localWorkoutId == null) {
          log('Skipping workout with invalid local ID: ${workout.id}');
          continue;
        }

        if (workout.endTime == null) {
          continue;
        }

        if (workout.remoteActivityId != null) {
          await _localDataSource.markWorkoutAsSyncedInLocalDatabase(
            localWorkoutId,
            userId: userId,
          );
          continue;
        }

        try {
          if (!await _pushWorkout(
            workout,
            localWorkoutId,
            authHeaders,
            userId,
          )) {
            return;
          }
        } on UnauthorizedException catch (_) {
          final refreshedAuthHeaders = await _refreshAuthHeaders(userId);
          if (refreshedAuthHeaders == null) {
            log(
              'Workout sync halted after auth refresh failed for ${workout.id}',
            );
            return;
          }
          authHeaders = refreshedAuthHeaders;

          try {
            if (!await _pushWorkout(
              workout,
              localWorkoutId,
              authHeaders,
              userId,
            )) {
              return;
            }
          } catch (retryError) {
            log(
              'Failed to sync workout ${workout.id} after auth refresh: '
              '$retryError',
            );
          }
        } on ForbiddenException catch (_) {
          final refreshedAuthHeaders = await _refreshAuthHeaders(userId);
          if (refreshedAuthHeaders == null) {
            log(
              'Workout sync halted after auth refresh failed for ${workout.id}',
            );
            return;
          }
          authHeaders = refreshedAuthHeaders;

          try {
            if (!await _pushWorkout(
              workout,
              localWorkoutId,
              authHeaders,
              userId,
            )) {
              return;
            }
          } catch (retryError) {
            log(
              'Failed to sync workout ${workout.id} after auth refresh: '
              '$retryError',
            );
          }
        } catch (e) {
          log('Failed to sync workout ${workout.id}: $e');
        }
      }
    } finally {
      _isSyncing = false;
      operationLease?.release();
    }
  }

  Future<bool> _pushWorkout(
    WorkoutSessionEntity workout,
    int localWorkoutId,
    Map<String, String> authHeaders,
    int userId,
  ) async {
    final activityJson = ActivitySyncModel.toJson(workout);
    final remoteActivityId = await _remoteDataSource.createActivity(
      activityJson,
      authHeaders,
    );
    if (!await _isCurrentUser(userId)) {
      return false;
    }

    return _localDataSource.recordWorkoutSyncSuccess(
      userId: userId,
      localWorkoutId: localWorkoutId,
      clientSyncId: workout.clientSyncId,
      remoteActivityId: remoteActivityId,
    );
  }

  Future<Map<String, String>?> _syncPendingWorkoutDeletes(
    int userId,
    Map<String, String> authHeaders,
  ) async {
    var currentAuthHeaders = authHeaders;
    final pendingDeletes = await _localDataSource.getWorkoutDeletesReadyForSync(
      userId,
      DateTime.now(),
    );

    for (final deleteEntry in pendingDeletes) {
      try {
        if (!await _deleteRemoteWorkout(
          deleteEntry,
          currentAuthHeaders,
          userId,
        )) {
          return null;
        }
      } on UnauthorizedException catch (_) {
        final refreshedAuthHeaders = await _refreshAuthHeaders(userId);
        if (refreshedAuthHeaders == null) {
          log(
            'Workout delete sync halted after auth refresh failed for '
            '${deleteEntry.remoteActivityId}',
          );
          await _markWorkoutDeleteRetrying(
            deleteEntry,
            'Auth refresh failed',
            userId,
          );
          return null;
        }
        currentAuthHeaders = refreshedAuthHeaders;

        try {
          if (!await _deleteRemoteWorkout(
            deleteEntry,
            currentAuthHeaders,
            userId,
            claimDelete: false,
          )) {
            return null;
          }
        } catch (retryError) {
          await _markWorkoutDeleteRetrying(deleteEntry, retryError, userId);
        }
      } on ForbiddenException catch (_) {
        final refreshedAuthHeaders = await _refreshAuthHeaders(userId);
        if (refreshedAuthHeaders == null) {
          log(
            'Workout delete sync halted after auth refresh failed for '
            '${deleteEntry.remoteActivityId}',
          );
          await _markWorkoutDeleteRetrying(
            deleteEntry,
            'Auth refresh failed',
            userId,
          );
          return null;
        }
        currentAuthHeaders = refreshedAuthHeaders;

        try {
          if (!await _deleteRemoteWorkout(
            deleteEntry,
            currentAuthHeaders,
            userId,
            claimDelete: false,
          )) {
            return null;
          }
        } catch (retryError) {
          await _markWorkoutDeleteRetrying(deleteEntry, retryError, userId);
        }
      } catch (error) {
        await _markWorkoutDeleteRetrying(deleteEntry, error, userId);
      }
    }

    return currentAuthHeaders;
  }

  Future<bool> _deleteRemoteWorkout(
    WorkoutDeleteQueueEntry deleteEntry,
    Map<String, String> authHeaders,
    int userId, {
    bool claimDelete = true,
  }) async {
    if (claimDelete) {
      final didClaim = await _localDataSource.markWorkoutDeleteDeleting(
        deleteEntry.id,
        userId: userId,
      );
      if (!didClaim) {
        return true;
      }
    }

    try {
      await _remoteDataSource.deleteActivity(
        deleteEntry.remoteActivityId,
        authHeaders,
      );
    } on NotFoundException {
      // Idempotent success: the server-side activity is already gone.
    }

    if (!await _isCurrentUser(userId)) {
      return false;
    }

    await _localDataSource.completeWorkoutDelete(
      queueId: deleteEntry.id,
      localWorkoutId: deleteEntry.localWorkoutId,
      userId: userId,
    );
    return true;
  }

  Future<void> _markWorkoutDeleteRetrying(
    WorkoutDeleteQueueEntry deleteEntry,
    Object error,
    int userId,
  ) async {
    if (!await _isCurrentUser(userId)) {
      return;
    }
    final retryCount = deleteEntry.retryCount + 1;
    await _localDataSource.markWorkoutDeleteRetrying(
      queueId: deleteEntry.id,
      userId: userId,
      retryCount: retryCount,
      error: error.toString(),
      nextRetryAt: DateTime.now().add(_workoutDeleteRetryDelay(retryCount)),
    );
    log(
      'Failed to delete remote workout ${deleteEntry.remoteActivityId}: $error',
    );
  }

  Duration _workoutDeleteRetryDelay(int retryCount) {
    if (retryCount <= 1) return const Duration(seconds: 30);
    if (retryCount == 2) return const Duration(minutes: 2);
    if (retryCount == 3) return const Duration(minutes: 5);
    if (retryCount == 4) return const Duration(minutes: 15);
    if (retryCount == 5) return const Duration(hours: 1);
    return const Duration(hours: 6);
  }

  Future<Map<String, String>?> _refreshAuthHeaders(int userId) async {
    try {
      await _authRepository.refreshToken();
      if (!await _isCurrentUser(userId)) {
        return null;
      }
      final authHeaders = await _authLocalDataSource.getAuthHeaders();
      if (!await _isCurrentUser(userId)) {
        return null;
      }
      return authHeaders;
    } catch (e) {
      log('Failed to refresh auth token during workout sync: $e');
      return null;
    }
  }

  Future<bool> _isCurrentUser(int userId) async {
    return await getCurrentUserId() == userId;
  }

  int? _parseLocalWorkoutId(String? workoutId) {
    if (workoutId == null || workoutId.trim().isEmpty) {
      return null;
    }

    return int.tryParse(workoutId);
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
