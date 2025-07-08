import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_details_state.dart';

// Notifier for managing workout details state
class TrackingHistoryDetailsNotifier
    extends StateNotifier<TrackingHistoryDetailsState> {
  final WorkoutRepository _workoutRepository;

  TrackingHistoryDetailsNotifier(this._workoutRepository)
    : super(const TrackingHistoryDetailsState());

  /// Load full workout details including tracking points and status changes
  Future<void> loadWorkoutDetails(String workoutId) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);

      // Parse workout ID
      final id = int.tryParse(workoutId);
      if (id == null) {
        throw Exception('Invalid workout ID');
      }

      // Fetch full workout data from repository
      final workout = await _workoutRepository.getWorkout(id);

      if (workout == null) {
        throw Exception('Workout not found');
      }

      state = state.copyWith(workout: workout, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load workout details: $e',
      );
    }
  }
}

// Provider for workout details
final trackingHistoryDetailsProvider = StateNotifierProvider.autoDispose<
  TrackingHistoryDetailsNotifier,
  TrackingHistoryDetailsState
>((ref) {
  final workoutRepository = ref.watch(workoutRepositoryProvider);
  return TrackingHistoryDetailsNotifier(workoutRepository);
});
