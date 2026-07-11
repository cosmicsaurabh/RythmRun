import 'tracking_point_entity.dart';
import 'status_change_event_entity.dart';

enum WorkoutType { running, walking, cycling, hiking }

enum WorkoutStatus { notStarted, active, paused, completed }

class WorkoutSessionEntity {
  static const int legacyMetricsVersion = 1;
  static const int currentMetricsVersion = 2;

  static bool isSupportedMetricsVersion(int version) =>
      version == legacyMetricsVersion || version == currentMetricsVersion;

  final String? id; // null for new sessions, set after saving
  final String clientSyncId;
  final int? remoteActivityId;
  final int metricsVersion;
  final WorkoutType type;
  final WorkoutStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final Duration? pausedDuration;

  // Metrics
  final double totalDistance; // in meters
  final double averageSpeed; // in m/s
  final double maxSpeed; // in m/s
  final double? averagePace; // in minutes per km
  final int? calories; // estimated calories burned
  final double? elevationGain; // in meters
  final double? elevationLoss; // in meters

  // Tracking data
  final List<TrackingPointEntity> trackingPoints;
  final List<StatusChangeEvent> statusChanges;

  // User info
  final int userId;
  final String? name; // optional workout name
  final String? notes; // optional notes

  const WorkoutSessionEntity({
    this.id,
    required this.clientSyncId,
    this.remoteActivityId,
    this.metricsVersion = currentMetricsVersion,
    required this.type,
    required this.status,
    this.startTime,
    this.endTime,
    this.pausedDuration,
    this.totalDistance = 0.0,
    this.averageSpeed = 0.0,
    this.maxSpeed = 0.0,
    this.averagePace,
    this.calories,
    this.elevationGain,
    this.elevationLoss,
    this.trackingPoints = const [],
    this.statusChanges = const [],
    required this.userId,
    this.name,
    this.notes,
  });

  /// Elapsed wall-clock duration, clamped when timestamps are corrupt.
  Duration? get wallClockDuration {
    if (startTime == null) return null;

    final endTimeOrNow = endTime ?? DateTime.now();
    final duration = endTimeOrNow.difference(startTime!);
    return duration.isNegative ? Duration.zero : duration;
  }

  /// Paused time normalized to the valid range for this workout.
  Duration get effectivePausedDuration {
    final duration = pausedDuration;
    if (duration == null || duration.isNegative) return Duration.zero;

    final wallDuration = wallClockDuration;
    if (wallDuration != null && duration > wallDuration) return wallDuration;

    return duration;
  }

  /// Duration of the workout (excluding normalized paused time).
  Duration? get activeDuration {
    final wallDuration = wallClockDuration;
    if (wallDuration == null) return null;

    return wallDuration - effectivePausedDuration;
  }

  /// Check if the workout is currently active (not paused or completed)
  bool get isActive => status == WorkoutStatus.active;

  /// Check if the workout is paused
  bool get isPaused => status == WorkoutStatus.paused;

  /// Check if the workout is completed
  bool get isCompleted => status == WorkoutStatus.completed;

  /// Create a copy with updated values
  WorkoutSessionEntity copyWith({
    String? id,
    String? clientSyncId,
    int? remoteActivityId,
    int? metricsVersion,
    WorkoutType? type,
    WorkoutStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    Duration? pausedDuration,
    double? totalDistance,
    double? averageSpeed,
    double? maxSpeed,
    double? averagePace,
    int? calories,
    double? elevationGain,
    double? elevationLoss,
    List<TrackingPointEntity>? trackingPoints,
    List<StatusChangeEvent>? statusChanges,
    int? userId,
    String? name,
    String? notes,
  }) {
    return WorkoutSessionEntity(
      id: id ?? this.id,
      clientSyncId: clientSyncId ?? this.clientSyncId,
      remoteActivityId: remoteActivityId ?? this.remoteActivityId,
      metricsVersion: metricsVersion ?? this.metricsVersion,
      type: type ?? this.type,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      pausedDuration: pausedDuration ?? this.pausedDuration,
      totalDistance: totalDistance ?? this.totalDistance,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      averagePace: averagePace ?? this.averagePace,
      calories: calories ?? this.calories,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      trackingPoints: trackingPoints ?? this.trackingPoints,
      statusChanges: statusChanges ?? this.statusChanges,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() {
    return 'WorkoutSessionEntity{id: $id, clientSyncId: $clientSyncId, '
        'remoteActivityId: $remoteActivityId, metricsVersion: $metricsVersion, '
        'type: $type, status: $status, '
        'distance: ${totalDistance}m}';
  }
}
