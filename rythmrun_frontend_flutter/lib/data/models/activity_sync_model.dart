import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';

class ActivitySyncModel {
  ActivitySyncModel._();

  /// Local workout -> JSON for POST /api/activities
  static Map<String, dynamic> toJson(WorkoutSessionEntity workout) {
    return {
      'clientSyncId': workout.clientSyncId,
      'metricsVersion': workout.metricsVersion,
      'type': workout.type.name,
      'startTime': workout.startTime!.toUtc().toIso8601String(),
      'endTime': workout.endTime!.toUtc().toIso8601String(),
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
                  'timestamp': point.timestamp.toUtc().toIso8601String(),
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
                  'timestamp': statusChange.timestamp.toUtc().toIso8601String(),
                },
              )
              .toList(),
    };
  }

  /// JSON from GET /api/activities -> Local workout entity
  static WorkoutSessionEntity fromJson(Map<String, dynamic> json, int userId) {
    final rawLocations = json['locations'] as List<dynamic>? ?? [];
    final trackingPoints =
        rawLocations.map((loc) {
          return TrackingPointEntity(
            latitude: (loc['latitude'] as num).toDouble(),
            longitude: (loc['longitude'] as num).toDouble(),
            altitude: (loc['altitude'] as num?)?.toDouble() ?? 0.0,
            timestamp: DateTime.parse(loc['timestamp'] as String).toLocal(),
            accuracy: (loc['accuracy'] as num?)?.toDouble() ?? 0.0,
            speed: (loc['speed'] as num?)?.toDouble() ?? 0.0,
            heading: (loc['heading'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();

    final rawStatusChanges = json['statusChanges'] as List<dynamic>? ?? [];
    final statusChanges =
        rawStatusChanges.map((sc) {
          return StatusChangeEvent(
            status: WorkoutStatus.values.firstWhere(
              (val) => val.name == sc['status'],
              orElse: () => WorkoutStatus.completed,
            ),
            timestamp: DateTime.parse(sc['timestamp'] as String).toLocal(),
          );
        }).toList();

    return WorkoutSessionEntity(
      clientSyncId: json['clientSyncId'] as String? ?? '',
      remoteActivityId: json['id'] as int?,
      metricsVersion: json['metricsVersion'] as int? ?? 2,
      type: WorkoutType.values.firstWhere(
        (val) => val.name == json['type'],
        orElse: () => WorkoutType.running,
      ),
      status: WorkoutStatus.completed, // Server records are completed
      startTime: DateTime.parse(json['startTime'] as String).toLocal(),
      endTime:
          json['endTime'] == null
              ? null
              : DateTime.parse(json['endTime'] as String).toLocal(),
      pausedDuration:
          json['pausedDuration'] == null
              ? null
              : Duration(seconds: json['pausedDuration'] as int),
      totalDistance: (json['distance'] as num).toDouble(),
      averageSpeed: (json['avgSpeed'] as num).toDouble(),
      maxSpeed: (json['maxSpeed'] as num).toDouble(),
      calories: json['calories'] as int?,
      elevationGain: (json['elevationGain'] as num?)?.toDouble(),
      elevationLoss: (json['elevationLoss'] as num?)?.toDouble(),
      name: json['name'] as String?,
      notes: json['description'] as String?,
      trackingPoints: trackingPoints,
      statusChanges: statusChanges,
      userId: userId,
    );
  }
}
