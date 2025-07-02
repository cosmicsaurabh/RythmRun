import 'tracking_point_entity.dart';

enum WorkoutType { running, walking, cycling, hiking }

enum WorkoutStatus { notStarted, active, paused, completed }

class WorkoutSessionEntity {
  final String? id; // null for new sessions, set after saving
  final WorkoutType type;
  final WorkoutStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final Duration? pausedDuration;

  // Metrics
  final double totalDistance; // in meters
  final double averageSpeed; // in m/s
  final double maxSpeed; // in m/s
  final double? averagePace; // in seconds per km
  final int? calories; // estimated calories burned
  final double? elevationGain; // in meters
  final double? elevationLoss; // in meters

  // Tracking data
  final List<TrackingPointEntity> trackingPoints;

  // User info
  final int userId;
  final String? name; // optional workout name
  final String? notes; // optional notes

  const WorkoutSessionEntity({
    this.id,
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
    required this.userId,
    this.name,
    this.notes,
  });

  /// Duration of the workout (excluding paused time)
  Duration? get activeDuration {
    if (startTime == null) return null;

    final endTimeOrNow = endTime ?? DateTime.now();
    final totalDuration = endTimeOrNow.difference(startTime!);
    final pausedTime = pausedDuration ?? Duration.zero;

    return totalDuration - pausedTime;
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
    int? userId,
    String? name,
    String? notes,
  }) {
    return WorkoutSessionEntity(
      id: id ?? this.id,
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
      userId: userId ?? this.userId,
      name: name ?? this.name,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() {
    return 'WorkoutSessionEntity{id: $id, type: $type, status: $status, distance: ${totalDistance}m}';
  }
}
