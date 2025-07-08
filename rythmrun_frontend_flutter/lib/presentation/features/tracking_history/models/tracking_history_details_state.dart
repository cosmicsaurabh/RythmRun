// State for tracking history details
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class TrackingHistoryDetailsState {
  final WorkoutSessionEntity? workout;
  final bool isLoading;
  final String? errorMessage;

  const TrackingHistoryDetailsState({
    this.workout,
    this.isLoading = false,
    this.errorMessage,
  });

  TrackingHistoryDetailsState copyWith({
    WorkoutSessionEntity? workout,
    bool? isLoading,
    String? errorMessage,
  }) {
    return TrackingHistoryDetailsState(
      workout: workout ?? this.workout,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
