import 'package:flutter/foundation.dart';
import '../../../../domain/entities/workout_session_entity.dart';

@immutable
class TrackingHistoryState {
  final List<WorkoutSessionEntity> workouts;
  final bool isLoading;
  final String? errorMessage;

  const TrackingHistoryState({
    this.workouts = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  TrackingHistoryState copyWith({
    List<WorkoutSessionEntity>? workouts,
    bool? isLoading,
    String? errorMessage,
  }) {
    return TrackingHistoryState(
      workouts: workouts ?? this.workouts,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackingHistoryState &&
          runtimeType == other.runtimeType &&
          workouts == other.workouts &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      workouts.hashCode ^ isLoading.hashCode ^ errorMessage.hashCode;

  @override
  String toString() {
    return 'WorkoutsListState{workouts: ${workouts.length}, isLoading: $isLoading, errorMessage: $errorMessage}';
  }
}
