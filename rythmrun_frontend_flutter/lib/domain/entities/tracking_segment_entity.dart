import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class TrackingSegment {
  final List<TrackingPointEntity> points;
  final WorkoutStatus status;

  const TrackingSegment({required this.points, required this.status});

  TrackingSegment copyWith({
    List<TrackingPointEntity>? points,
    WorkoutStatus? status,
  }) {
    return TrackingSegment(
      points: points ?? this.points,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'TrackingSegment(pointCount: ${points.length}, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrackingSegment &&
        other.status == status &&
        other.points.length == points.length;
  }

  @override
  int get hashCode => points.length.hashCode ^ status.hashCode;
}
