import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_state.dart';

// Notifier for managing workout list state
class TrackingHistoryNotifier extends StateNotifier<TrackingHistoryState> {
  final WorkoutRepository _workoutRepository;

  TrackingHistoryNotifier(this._workoutRepository)
    : super(const TrackingHistoryState()) {
    // Load initial data
    loadInitialData();
  }

  /// Load initial data (first page)
  Future<void> loadInitialData() async {
    try {
      state = state.copyWith(isLoading: true, clearErrorMessage: true);

      // Load first page of workouts
      final paginatedWorkouts = await _workoutRepository.getPaginatedWorkouts(
        page: 1,
        limit: state.limit,
        workoutType: state.selectedWorkoutType,
        startDate: state.startDate,
        endDate: state.endDate,
        loadTrackingPoints: false, // Don't load tracking points for list view
      );

      // Load overall statistics (no filters)
      final overallStats = await _workoutRepository.getWorkoutStatistics();

      // Load filtered statistics (with current filters)
      final filteredStats = await _workoutRepository.getWorkoutStatistics(
        workoutType: state.selectedWorkoutType,
        startDate: state.startDate,
        endDate: state.endDate,
      );

      state = state.copyWith(
        workouts: paginatedWorkouts.workouts,
        isLoading: false,
        currentPage: 1,
        totalPages: (paginatedWorkouts.totalCount / state.limit).ceil(),
        totalCount: paginatedWorkouts.totalCount,
        hasNextPage: paginatedWorkouts.workouts.length >= state.limit,
        hasPreviousPage: false,
        overallStatistics: overallStats,
        filteredStatistics: filteredStats,
        isLoadingStats: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load workouts: $e',
      );
    }
  }

  /// Load more workouts for infinite scroll
  Future<void> loadMoreWorkouts() async {
    // Don't load if already loading or no more pages
    if (state.isLoading || state.isLoadingMore || !state.hasNextPage) {
      print(
        '🚫 Skipping loadMoreWorkouts: isLoading=${state.isLoading}, isLoadingMore=${state.isLoadingMore}, hasNextPage=${state.hasNextPage}',
      );
      return;
    }

    try {
      print('📄 Loading more workouts - page ${state.currentPage + 1}');
      state = state.copyWith(isLoadingMore: true);

      final nextPage = state.currentPage + 1;

      // Load next page of workouts
      final paginatedWorkouts = await _workoutRepository.getPaginatedWorkouts(
        page: nextPage,
        limit: state.limit,
        workoutType: state.selectedWorkoutType,
        startDate: state.startDate,
        endDate: state.endDate,
        loadTrackingPoints: false,
      );

      // Append new workouts to existing list
      final updatedWorkouts = [
        ...state.workouts,
        ...paginatedWorkouts.workouts,
      ];

      print(
        '✅ Loaded ${paginatedWorkouts.workouts.length} more workouts. Total: ${updatedWorkouts.length}',
      );

      state = state.copyWith(
        workouts: updatedWorkouts,
        currentPage: nextPage,
        hasNextPage: paginatedWorkouts.workouts.length >= state.limit,
        hasPreviousPage: nextPage > 1,
        isLoadingMore: false,
      );
    } catch (e) {
      print('❌ Error loading more workouts: $e');
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: 'Failed to load more workouts: $e',
      );
    }
  }

  /// Set workout type filter
  Future<void> setWorkoutTypeFilter(String? workoutType) async {
    if (state.selectedWorkoutType != workoutType) {
      if (workoutType == null) {
        state = state.copyWith(
          clearSelectedWorkoutType: true,
          isLoadingStats: true,
        );
      } else {
        state = state.copyWith(
          selectedWorkoutType: workoutType,
          isLoadingStats: true,
        );
      }
      await loadInitialData(); // Reload with new filter
    }
  }

  /// Set date range filter
  Future<void> setDateRangeFilter({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (state.startDate != startDate || state.endDate != endDate) {
      state = state.copyWith(
        startDate: startDate,
        endDate: endDate,
        clearStartDate: startDate == null,
        clearEndDate: endDate == null,
        isLoadingStats: true,
      );
      await loadInitialData();
    }
  }

  Future<void> clearFilters() async {
    if (state.hasFilters) {
      state = state.clearFilters().copyWith(isLoadingStats: true);
      await loadInitialData();
    }
  }

  /// Delete a workout
  Future<void> deleteWorkout(String workoutId) async {
    try {
      final id = int.tryParse(workoutId);
      if (id == null) {
        throw Exception('Invalid workout ID');
      }

      await _workoutRepository.deleteWorkout(id);

      // Reload initial data to reflect changes
      await loadInitialData();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete workout: $e');
    }
  }

  /// Refresh the workout list
  Future<void> refresh() async {
    await loadInitialData();
  }

  /// Get workout type options for filtering
  List<String> getWorkoutTypeOptions() {
    return ['running', 'walking', 'cycling', 'hiking'];
  }

  /// Get formatted overall stats text for app bar
  String getOverallStatsText() {
    final stats = state.overallStatistics;
    if (stats == null || stats.totalWorkouts == 0) {
      return 'No workouts yet';
    }

    return '${stats.totalWorkouts} workouts • ${stats.formattedTotalDistance} • ${stats.formattedTotalDuration}';
  }

  /// Get formatted filtered stats text for filter card
  String getFilteredStatsText() {
    final stats = state.filteredStatistics;
    if (stats == null || stats.totalWorkouts == 0) {
      return state.hasFilters ? 'No workouts match filters' : 'No workouts yet';
    }

    final suffix = state.hasFilters ? ' (filtered)' : '';
    return '${stats.totalWorkouts} workouts • ${stats.formattedTotalDistance} • ${stats.formattedTotalDuration}$suffix';
  }

  /// Check if showing all workouts or filtered subset
  bool get isShowingFilteredData => state.hasFilters;
}

// Provider for workout list
final trackingHistoryProvider =
    StateNotifierProvider<TrackingHistoryNotifier, TrackingHistoryState>((ref) {
      final workoutRepository = ref.watch(workoutRepositoryProvider);
      return TrackingHistoryNotifier(workoutRepository);
    });

// Convenience providers
final hasWorkoutsProvider = Provider<bool>((ref) {
  return ref.watch(
    trackingHistoryProvider.select((state) => state.workouts.isNotEmpty),
  );
});

final workoutCountProvider = Provider<int>((ref) {
  return ref.watch(trackingHistoryProvider.select((state) => state.totalCount));
});

final overallStatisticsProvider = Provider<WorkoutStatistics?>((ref) {
  return ref.watch(
    trackingHistoryProvider.select((state) => state.overallStatistics),
  );
});

final filteredStatisticsProvider = Provider<WorkoutStatistics?>((ref) {
  return ref.watch(
    trackingHistoryProvider.select((state) => state.filteredStatistics),
  );
});

final isLoadingWorkoutsProvider = Provider<bool>((ref) {
  return ref.watch(trackingHistoryProvider.select((state) => state.isLoading));
});

final isLoadingMoreWorkoutsProvider = Provider<bool>((ref) {
  return ref.watch(
    trackingHistoryProvider.select((state) => state.isLoadingMore),
  );
});

final hasFiltersProvider = Provider<bool>((ref) {
  return ref.watch(trackingHistoryProvider.select((state) => state.hasFilters));
});
