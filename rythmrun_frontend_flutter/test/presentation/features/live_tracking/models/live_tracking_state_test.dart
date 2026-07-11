import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';

void main() {
  group('LiveTrackingState metric presentation', () {
    test('formats average and maximum m/s through the same km/h contract', () {
      final state = LiveTrackingState(
        currentSession: _workout(
          averageSpeed: 2.7777777777777777,
          maxSpeed: 5.555555555555555,
        ),
      );

      expect(state.formattedAverageSpeed, '10.0 km/h');
      expect(state.formattedMaxSpeed, '20.0 km/h');
    });

    test('uses safe zero speed when session values are absent or invalid', () {
      expect(const LiveTrackingState().formattedAverageSpeed, '0.0 km/h');
      expect(const LiveTrackingState().formattedMaxSpeed, '0.0 km/h');

      final invalidState = LiveTrackingState(
        currentSession: _workout(
          averageSpeed: double.nan,
          maxSpeed: double.infinity,
        ),
      );

      expect(invalidState.formattedAverageSpeed, '0.0 km/h');
      expect(invalidState.formattedMaxSpeed, '0.0 km/h');
    });

    test('continues to format pace as minutes and seconds per kilometre', () {
      expect(LiveTrackingState(currentPace: 5).formattedPace, '5:00');
      expect(LiveTrackingState(currentPace: 5.999).formattedPace, '6:00');
      expect(LiveTrackingState(currentPace: double.nan).formattedPace, '--:--');
      expect(
        LiveTrackingState(currentPace: double.infinity).formattedPace,
        '--:--',
      );
    });
  });
}

WorkoutSessionEntity _workout({
  required double averageSpeed,
  required double maxSpeed,
}) {
  return WorkoutSessionEntity(
    clientSyncId: 'metric-state-test',
    type: WorkoutType.running,
    status: WorkoutStatus.active,
    averageSpeed: averageSpeed,
    maxSpeed: maxSpeed,
    userId: 1,
  );
}
