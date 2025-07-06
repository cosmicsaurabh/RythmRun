import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_segment_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';

class LiveMapSegmentBuilder {
  /// Build segments from workout session data
  static List<TrackingSegment> buildSegments(WorkoutSessionEntity session) {
    if (session.trackingPoints.isEmpty) return [];

    final segments = <TrackingSegment>[];
    WorkoutStatus currentStatus = WorkoutStatus.active; // Default start status
    int segmentStart = 0;

    print(
      '🔧 Building segments from ${session.trackingPoints.length} points and ${session.statusChanges.length} status changes',
    );

    for (int i = 0; i < session.trackingPoints.length; i++) {
      final point = session.trackingPoints[i];

      // Check if status changed at this point's timestamp
      final statusAtPoint = _getStatusAtTime(
        point.timestamp,
        session.statusChanges,
      );

      if (statusAtPoint != currentStatus) {
        // Close current segment if it has points
        if (i > segmentStart) {
          final segmentPoints = session.trackingPoints.sublist(segmentStart, i);
          segments.add(
            TrackingSegment(points: segmentPoints, status: currentStatus),
          );
          print(
            '✅ Created segment: ${segmentPoints.length} points, status: $currentStatus',
          );
        }

        // Start new segment
        currentStatus = statusAtPoint;
        segmentStart = i;
      }
    }

    // Add final segment
    if (segmentStart < session.trackingPoints.length) {
      final segmentPoints = session.trackingPoints.sublist(segmentStart);
      segments.add(
        TrackingSegment(points: segmentPoints, status: currentStatus),
      );
      print(
        '✅ Created final segment: ${segmentPoints.length} points, status: $currentStatus',
      );
    }

    print('🎯 Total segments created: ${segments.length}');
    return segments;
  }

  /// Get the workout status at a specific timestamp
  static WorkoutStatus _getStatusAtTime(
    DateTime time,
    List<StatusChangeEvent> changes,
  ) {
    WorkoutStatus currentStatus = WorkoutStatus.active; // Default start status

    // Go through all status changes up to this point's time
    for (final change in changes) {
      if (change.timestamp.isBefore(time) ||
          change.timestamp.isAtSameMomentAs(time)) {
        currentStatus = change.status;
      }
    }

    return currentStatus;
  }

  /// Helper to get segments by status
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

  /// Debug helper to print segment information
  static void debugSegments(List<TrackingSegment> segments) {
    print('📊 Segment Debug Info:');
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      print(
        '  Segment $i: ${segment.points.length} points, status: ${segment.status}',
      );
      if (segment.points.isNotEmpty) {
        print('    Start: ${segment.points.first.timestamp}');
        print('    End: ${segment.points.last.timestamp}');
      }
    }
  }
}
