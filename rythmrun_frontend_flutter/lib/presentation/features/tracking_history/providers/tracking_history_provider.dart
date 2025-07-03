import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/repositories/workout_repository.dart';
import '../../../../core/di/injection_container.dart';
import '../models/tracking_history_state.dart';

// Notifier for managing workout list state
class TrackingHistoryNotifier extends StateNotifier<TrackingHistoryState> {
  final WorkoutRepository _workoutRepository;

  TrackingHistoryNotifier(this._workoutRepository)
    : super(const TrackingHistoryState()) {
    loadTrackingHistory();
  }

  /// Load all workouts from the database
  Future<void> loadTrackingHistory() async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);

      final workouts = await _workoutRepository.getWorkouts();

      state = state.copyWith(workouts: workouts, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load workouts: $e',
      );
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

      // Reload the list
      await loadTrackingHistory();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete workout: $e');
    }
  }

  /// Refresh the workout list
  Future<void> refresh() async {
    await loadTrackingHistory();
  }
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
  return ref.watch(
    trackingHistoryProvider.select((state) => state.workouts.length),
  );
});
