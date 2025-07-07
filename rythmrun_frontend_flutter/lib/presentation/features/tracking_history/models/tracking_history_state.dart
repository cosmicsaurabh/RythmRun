import 'package:flutter/foundation.dart';
import '../../../../domain/entities/workout_session_entity.dart';
import '../../../../core/services/local_db_service.dart';

@immutable
class TrackingHistoryState {
  final List<WorkoutSessionEntity> workouts;
  final bool isLoading;
  final String? errorMessage;

  // Pagination
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final int limit;

  // Filtering
  final String? selectedWorkoutType;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? searchQuery;

  // Statistics
  final WorkoutStatistics? statistics;
  final bool isLoadingStats;

  const TrackingHistoryState({
    this.workouts = const [],
    this.isLoading = false,
    this.errorMessage,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.limit = 20,
    this.selectedWorkoutType,
    this.startDate,
    this.endDate,
    this.searchQuery,
    this.statistics,
    this.isLoadingStats = false,
  });

  TrackingHistoryState copyWith({
    List<WorkoutSessionEntity>? workouts,
    bool? isLoading,
    String? errorMessage,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    bool? hasNextPage,
    bool? hasPreviousPage,
    int? limit,
    String? selectedWorkoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    WorkoutStatistics? statistics,
    bool? isLoadingStats,
  }) {
    return TrackingHistoryState(
      workouts: workouts ?? this.workouts,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
      limit: limit ?? this.limit,
      selectedWorkoutType: selectedWorkoutType ?? this.selectedWorkoutType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      searchQuery: searchQuery ?? this.searchQuery,
      statistics: statistics ?? this.statistics,
      isLoadingStats: isLoadingStats ?? this.isLoadingStats,
    );
  }

  // Clear filters
  TrackingHistoryState clearFilters() {
    return copyWith(
      selectedWorkoutType: null,
      startDate: null,
      endDate: null,
      searchQuery: null,
      currentPage: 1,
    );
  }

  // Check if any filters are applied
  bool get hasFilters {
    return selectedWorkoutType != null ||
        startDate != null ||
        endDate != null ||
        (searchQuery != null && searchQuery!.isNotEmpty);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackingHistoryState &&
          runtimeType == other.runtimeType &&
          workouts == other.workouts &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage &&
          currentPage == other.currentPage &&
          totalPages == other.totalPages &&
          totalCount == other.totalCount &&
          hasNextPage == other.hasNextPage &&
          hasPreviousPage == other.hasPreviousPage &&
          limit == other.limit &&
          selectedWorkoutType == other.selectedWorkoutType &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          searchQuery == other.searchQuery &&
          statistics == other.statistics &&
          isLoadingStats == other.isLoadingStats;

  @override
  int get hashCode =>
      workouts.hashCode ^
      isLoading.hashCode ^
      errorMessage.hashCode ^
      currentPage.hashCode ^
      totalPages.hashCode ^
      totalCount.hashCode ^
      hasNextPage.hashCode ^
      hasPreviousPage.hashCode ^
      limit.hashCode ^
      selectedWorkoutType.hashCode ^
      startDate.hashCode ^
      endDate.hashCode ^
      searchQuery.hashCode ^
      statistics.hashCode ^
      isLoadingStats.hashCode;

  @override
  String toString() {
    return 'TrackingHistoryState{workouts: ${workouts.length}, isLoading: $isLoading, errorMessage: $errorMessage, currentPage: $currentPage, totalPages: $totalPages, totalCount: $totalCount, hasFilters: $hasFilters}';
  }
}
