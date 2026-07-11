import 'package:flutter/foundation.dart';
import '../../../../domain/entities/workout_session_entity.dart';
import '../../../../core/services/local_db_service.dart';

@immutable
class TrackingHistoryState {
  static const Object _unset = Object();

  final List<WorkoutSessionEntity> workouts;
  final bool isLoading;
  final bool isLoadingMore;
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
    this.isLoadingMore = false,
    this.errorMessage,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.limit = 10,
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
    bool? isLoadingMore,
    Object? errorMessage = _unset,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    bool? hasNextPage,
    bool? hasPreviousPage,
    int? limit,
    Object? selectedWorkoutType = _unset,
    Object? startDate = _unset,
    Object? endDate = _unset,
    Object? searchQuery = _unset,
    Object? overallStatistics = _unset,
    Object? filteredStatistics = _unset,
    bool? isLoadingStats,
  }) {
    return TrackingHistoryState(
      workouts: workouts ?? this.workouts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
      limit: limit ?? this.limit,
      selectedWorkoutType:
          identical(selectedWorkoutType, _unset)
              ? this.selectedWorkoutType
              : selectedWorkoutType as String?,
      startDate:
          identical(startDate, _unset)
              ? this.startDate
              : startDate as DateTime?,
      endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      searchQuery:
          identical(searchQuery, _unset)
              ? this.searchQuery
              : searchQuery as String?,
      overallStatistics:
          identical(overallStatistics, _unset)
              ? this.overallStatistics
              : overallStatistics as WorkoutStatistics?,
      filteredStatistics:
          identical(filteredStatistics, _unset)
              ? this.filteredStatistics
              : filteredStatistics as WorkoutStatistics?,
      isLoadingStats: isLoadingStats ?? this.isLoadingStats,
    );
  }

  // Clear filters
  TrackingHistoryState clearFilters() {
    return copyWith(
      currentPage: 1,
      selectedWorkoutType: null,
      startDate: null,
      endDate: null,
      searchQuery: null,
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
          isLoadingMore == other.isLoadingMore &&
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
      isLoadingMore.hashCode ^
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
    return 'TrackingHistoryState{workouts: ${workouts.length}, isLoading: $isLoading, isLoadingMore: $isLoadingMore, errorMessage: $errorMessage, currentPage: $currentPage, totalPages: $totalPages, totalCount: $totalCount, hasFilters: $hasFilters}';
  }
}
