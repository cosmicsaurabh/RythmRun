import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/data/models/activity_sync_model.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

void main() {
  group('ActivitySyncModel metric contract', () {
    test('emits canonical version 2 speeds in metres per second', () {
      final workout = _workout(
        metricsVersion: 2,
        averageSpeed: 2.7777777777777777,
        maxSpeed: 4.5,
      );

      final json = ActivitySyncModel.toJson(workout);

      expect(json['metricsVersion'], 2);
      expect(json['avgSpeed'], closeTo(2.7777777778, 0.0000000001));
      expect(json['maxSpeed'], 4.5);
      expect(json['duration'], 3600);
      expect(json['pausedDuration'], isNull);

      final locations = json['locations']! as List<dynamic>;
      final firstLocation = locations.single as Map<String, dynamic>;
      expect(firstLocation['speed'], 3.25);
    });

    test('tags legacy values without silently transforming them', () {
      final workout = _workout(
        metricsVersion: 1,
        averageSpeed: 10,
        maxSpeed: 4.5,
      );

      final json = ActivitySyncModel.toJson(workout);

      expect(json['metricsVersion'], 1);
      expect(json['avgSpeed'], 10);
      expect(json['maxSpeed'], 4.5);
    });

    test('normalizes corrupt paused time before sync', () {
      final negativePause = ActivitySyncModel.toJson(
        _workout(
          metricsVersion: 2,
          averageSpeed: 2,
          maxSpeed: 4,
          pausedDuration: const Duration(seconds: -60),
        ),
      );
      final overlongPause = ActivitySyncModel.toJson(
        _workout(
          metricsVersion: 2,
          averageSpeed: 2,
          maxSpeed: 4,
          pausedDuration: const Duration(hours: 2),
        ),
      );

      expect(negativePause['pausedDuration'], 0);
      expect(negativePause['duration'], 3600);
      expect(overlongPause['pausedDuration'], 3600);
      expect(overlongPause['duration'], 0);
    });
  });
}

WorkoutSessionEntity _workout({
  required int metricsVersion,
  required double averageSpeed,
  required double maxSpeed,
  Duration? pausedDuration,
}) {
  final startTime = DateTime.utc(2026, 7, 11, 6);

  return WorkoutSessionEntity(
    clientSyncId: 'metric-sync-v$metricsVersion',
    metricsVersion: metricsVersion,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: startTime,
    endTime: startTime.add(const Duration(hours: 1)),
    pausedDuration: pausedDuration,
    totalDistance: 10000,
    averageSpeed: averageSpeed,
    maxSpeed: maxSpeed,
    averagePace: 6,
    calories: 770,
    trackingPoints: [
      TrackingPointEntity(
        latitude: 12.34,
        longitude: 56.78,
        speed: 3.25,
        timestamp: startTime,
      ),
    ],
    userId: 1,
  );
}
