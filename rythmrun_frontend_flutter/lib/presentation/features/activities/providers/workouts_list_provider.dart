import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/workout_session_entity.dart';
import '../../../../domain/repositories/workout_repository.dart';
import '../../../../core/di/injection_container.dart';
import '../models/workouts_list_state.dart';

// Notifier for managing workout list state
class WorkoutsListNotifier extends StateNotifier<WorkoutsListState> {
  final WorkoutRepository _repository;

  WorkoutsListNotifier(this._repository) : super(const WorkoutsListState()) {
    loadWorkouts();
  }

  /// Load all workouts from the database
  Future<void> loadWorkouts() async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);

      final workouts = await _repository.getWorkouts();

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

      await _repository.deleteWorkout(id);

      // Reload the list
      await loadWorkouts();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete workout: $e');
    }
  }

  /// Refresh the workout list
  Future<void> refresh() async {
    await loadWorkouts();
  }
}

// Provider for workout list
final workoutsListProvider =
    StateNotifierProvider<WorkoutsListNotifier, WorkoutsListState>((ref) {
      final repository = ref.watch(workoutRepositoryProvider);
      return WorkoutsListNotifier(repository);
    });

// Convenience providers
final hasWorkoutsProvider = Provider<bool>((ref) {
  return ref.watch(
    workoutsListProvider.select((state) => state.workouts.isNotEmpty),
  );
});

final workoutCountProvider = Provider<int>((ref) {
  return ref.watch(
    workoutsListProvider.select((state) => state.workouts.length),
  );
});

final recentWorkoutsProvider = Provider<List<WorkoutSessionEntity>>((ref) {
  final workouts = ref.watch(
    workoutsListProvider.select((state) => state.workouts),
  );
  // Return up to 5 most recent workouts
  return workouts.take(5).toList();
});
