import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';

/// Gives one newly committed workout at most one post-activity ad request.
///
/// Save retries and cleanup recovery deliberately do not call this gate. An ad
/// is optional; retaining and recovering the workout always has priority.
class WorkoutCompletionAdGate {
  final Set<int> _claimedWorkoutIds = <int>{};

  Future<bool> showAfterDurableCompletion({
    required LiveWorkoutFinalizationResult result,
    required bool hasPendingRecovery,
    required bool Function() isCurrentUserScope,
    required Future<void> Function() showAd,
  }) async {
    final localWorkoutId = result.localWorkoutId;
    if (!result.isNewlySaved ||
        localWorkoutId == null ||
        hasPendingRecovery ||
        !isCurrentUserScope() ||
        !_claimedWorkoutIds.add(localWorkoutId)) {
      return false;
    }

    try {
      await showAd();
    } catch (_) {
      // A committed workout remains successful when optional ads fail.
    }
    return true;
  }
}
