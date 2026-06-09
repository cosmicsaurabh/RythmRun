import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';

class SyncCoordinator {
  final WorkoutRepository _workoutRepository;
  final ActivityImageRepository _activityImageRepository;

  SyncCoordinator(this._workoutRepository, this._activityImageRepository);

  Future<void> syncAll() async {
    await _workoutRepository.syncWorkouts();
    await _activityImageRepository.syncPendingImages();
  }
}
