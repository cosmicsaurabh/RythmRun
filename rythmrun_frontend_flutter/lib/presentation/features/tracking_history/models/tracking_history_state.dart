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

  // Statistics (Two types for AppBar vs Filter cards)
  final WorkoutStatistics? overallStatistics; // For AppBar (all workouts)
  final WorkoutStatistics?
  filteredStatistics; // For Filter card (filtered workouts)
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
    this.overallStatistics,
    this.filteredStatistics,
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
    WorkoutStatistics? overallStatistics,
    WorkoutStatistics? filteredStatistics,
    bool? isLoadingStats,
    bool clearSelectedWorkoutType = false,
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearSearchQuery = false,
    bool clearErrorMessage = false,
  }) {
    return TrackingHistoryState(
      workouts: workouts ?? this.workouts,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
      limit: limit ?? this.limit,
      selectedWorkoutType:
          clearSelectedWorkoutType
              ? null
              : (selectedWorkoutType ?? this.selectedWorkoutType),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      overallStatistics: overallStatistics ?? this.overallStatistics,
      filteredStatistics: filteredStatistics ?? this.filteredStatistics,
      isLoadingStats: isLoadingStats ?? this.isLoadingStats,
    );
  }

  // Clear filters
  TrackingHistoryState clearFilters() {
    return copyWith(
      currentPage: 1,
      clearSelectedWorkoutType: true,
      clearStartDate: true,
      clearEndDate: true,
      clearSearchQuery: true,
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
          overallStatistics == other.overallStatistics &&
          filteredStatistics == other.filteredStatistics &&
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
      overallStatistics.hashCode ^
      filteredStatistics.hashCode ^
      isLoadingStats.hashCode;

  @override
  String toString() {
    return 'TrackingHistoryState{workouts: ${workouts.length}, isLoading: $isLoading, errorMessage: $errorMessage, currentPage: $currentPage, totalPages: $totalPages, totalCount: $totalCount, hasFilters: $hasFilters}';
  }
}
