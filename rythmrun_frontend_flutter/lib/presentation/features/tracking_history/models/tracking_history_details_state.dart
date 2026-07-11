// State for tracking history details
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class TrackingHistoryDetailsState {
  static const Object _unset = Object();

  final WorkoutSessionEntity? workout;
  final bool isLoading;
  final String? errorMessage;

  const TrackingHistoryDetailsState({
    this.workout,
    this.isLoading = false,
    this.errorMessage,
  });

  TrackingHistoryDetailsState copyWith({
    Object? workout = _unset,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return TrackingHistoryDetailsState(
      workout:
          identical(workout, _unset)
              ? this.workout
              : workout as WorkoutSessionEntity?,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
    );
  }
}
