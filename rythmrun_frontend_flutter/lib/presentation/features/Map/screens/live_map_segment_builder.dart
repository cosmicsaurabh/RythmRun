import 'package:rythmrun_frontend_flutter/core/tracking/workout_route_segmenter.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_segment_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class LiveMapSegmentBuilder {
  static List<TrackingSegment> buildSegments(WorkoutSessionEntity session) {
    return WorkoutRouteSegmenter.buildSegments(session);
  }

  static List<TrackingSegment> getActiveSegments(
    List<TrackingSegment> segments,
  ) {
    return segments
        .where((segment) => segment.status == WorkoutStatus.active)
        .toList();
  }

  static List<TrackingSegment> getPausedSegments(
    List<TrackingSegment> segments,
  ) {
    return segments
        .where((segment) => segment.status == WorkoutStatus.paused)
        .toList();
  }
}
