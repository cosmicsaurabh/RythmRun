import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class ActivitySyncModel {
  ActivitySyncModel._();

  /// Local workout -> JSON for POST /api/activities
  static Map<String, dynamic> toJson(WorkoutSessionEntity workout) {
    return {
      'clientSyncId': workout.clientSyncId,
      'metricsVersion': workout.metricsVersion,
      'type': workout.type.name,
      'startTime': workout.startTime!.toIso8601String(),
      'endTime': workout.endTime!.toIso8601String(),
      'distance': workout.totalDistance,
      'duration': workout.activeDuration!.inSeconds,
      'avgSpeed': workout.averageSpeed,
      'maxSpeed': workout.maxSpeed,
      'calories': workout.calories,
      'description': workout.notes,
      'name': workout.name,
      'pausedDuration':
          workout.pausedDuration == null
              ? null
              : workout.effectivePausedDuration.inSeconds,
      'elevationGain': workout.elevationGain,
      'elevationLoss': workout.elevationLoss,
      'isPublic': false,
      'locations':
          workout.trackingPoints
              .map(
                (point) => <String, dynamic>{
                  'latitude': point.latitude,
                  'longitude': point.longitude,
                  'altitude': point.altitude,
                  'timestamp': point.timestamp.toIso8601String(),
                  'accuracy': point.accuracy,
                  'speed': point.speed,
                  'heading': point.heading,
                },
              )
              .toList(),
      'statusChanges':
          workout.statusChanges
              .map(
                (statusChange) => <String, dynamic>{
                  'status': statusChange.status.name,
                  'timestamp': statusChange.timestamp.toIso8601String(),
                },
              )
              .toList(),
    };
  }
}
