import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
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

    test('omitted nullable values retain and explicit null clears them', () {
      final workout = _workout(averageSpeed: 1, maxSpeed: 2);
      final location = TrackingPointEntity(
        latitude: 12,
        longitude: 77,
        timestamp: DateTime.utc(2026, 7, 11),
      );
      final original = LiveTrackingState(
        currentSession: workout,
        currentLocation: location,
        errorMessage: 'old error',
        locationServiceStatus: LocationServiceStatus.permissionDenied,
      );

      final retained = original.copyWith();
      expect(retained.currentSession, same(workout));
      expect(retained.currentLocation, same(location));
      expect(retained.errorMessage, 'old error');
      expect(
        retained.locationServiceStatus,
        LocationServiceStatus.permissionDenied,
      );

      final cleared = original.copyWith(
        currentSession: null,
        currentLocation: null,
        errorMessage: null,
        locationServiceStatus: null,
      );
      expect(cleared.currentSession, isNull);
      expect(cleared.currentLocation, isNull);
      expect(cleared.errorMessage, isNull);
      expect(cleared.locationServiceStatus, isNull);
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
