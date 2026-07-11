import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_details_state.dart';

// Notifier for managing workout details state
class TrackingHistoryDetailsNotifier
    extends StateNotifier<TrackingHistoryDetailsState> {
  final WorkoutRepository _workoutRepository;
  final int _expectedUserId;
  bool _isDisposed = false;

  TrackingHistoryDetailsNotifier(
    this._workoutRepository, {
    required int expectedUserId,
  }) : _expectedUserId = expectedUserId,
       super(const TrackingHistoryDetailsState());

  /// Load full workout details including tracking points and status changes
  Future<void> loadWorkoutDetails(String workoutId) async {
    try {
      state = state.copyWith(
        workout: null,
        isLoading: true,
        errorMessage: null,
      );

      // Parse workout ID
      final id = int.tryParse(workoutId);
      if (id == null) {
        throw Exception('Invalid workout ID');
      }

      // Fetch full workout data from repository
      final workout = await _workoutRepository.getWorkout(id);
      if (_isDisposed) return;

      if (workout == null) {
        throw Exception('Workout not found');
      }
      if (workout.userId != _expectedUserId) {
        state = state.copyWith(
          workout: null,
          isLoading: false,
          errorMessage: 'Workout details are not available for this account.',
        );
        return;
      }

      state = state.copyWith(
        workout: workout,
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      if (_isDisposed) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load workout details: $e',
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

// Provider for workout details
final trackingHistoryDetailsProvider = StateNotifierProvider.autoDispose.family<
  TrackingHistoryDetailsNotifier,
  TrackingHistoryDetailsState,
  ({int userId, int workoutId})
>((ref, key) {
  final workoutRepository = ref.watch(workoutRepositoryProvider);
  return TrackingHistoryDetailsNotifier(
    workoutRepository,
    expectedUserId: key.userId,
  )..loadWorkoutDetails(key.workoutId.toString());
});
