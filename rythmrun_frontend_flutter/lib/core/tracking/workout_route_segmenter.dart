import 'package:rythmrun_frontend_flutter/core/tracking/gps_point_acceptance_policy.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_segment_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class WorkoutRouteSegmenter {
  const WorkoutRouteSegmenter._();

  static List<TrackingSegment> buildSegments(WorkoutSessionEntity session) {
    final points = session.trackingPoints;
    if (points.isEmpty) return const <TrackingSegment>[];

    final segments = <TrackingSegment>[];
    final usesAcceptedOnlyRoute =
        session.metricsVersion >= WorkoutSessionEntity.currentMetricsVersion;
    var currentStatus =
        usesAcceptedOnlyRoute
            ? WorkoutStatus.active
            : _statusAt(points.first.timestamp, session.statusChanges);
    var currentPoints = <TrackingPointEntity>[points.first];

    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final status =
          usesAcceptedOnlyRoute
              ? WorkoutStatus.active
              : _statusAt(current.timestamp, session.statusChanges);
      final hasTransition = _breaksAcceptedRouteBetween(
        previous.timestamp,
        current.timestamp,
        session.statusChanges,
      );
      final hasVersionTwoGap =
          session.metricsVersion >=
              WorkoutSessionEntity.currentMetricsVersion &&
          current.timestamp.difference(previous.timestamp) >
              GpsPointAcceptancePolicy.activeAnchorResetGap;

      if (status != currentStatus || hasTransition || hasVersionTwoGap) {
        segments.add(
          TrackingSegment(
            points: List<TrackingPointEntity>.unmodifiable(currentPoints),
            status: currentStatus,
          ),
        );
        currentStatus = status;
        currentPoints = <TrackingPointEntity>[current];
      } else {
        currentPoints.add(current);
      }
    }

    segments.add(
      TrackingSegment(
        points: List<TrackingPointEntity>.unmodifiable(currentPoints),
        status: currentStatus,
      ),
    );
    return List.unmodifiable(segments);
  }

  static List<List<TrackingPointEntity>> buildActivePointSegments(
    WorkoutSessionEntity session,
  ) {
    return buildSegments(session)
        .where((segment) => segment.status == WorkoutStatus.active)
        .map<List<TrackingPointEntity>>(
          (segment) => List<TrackingPointEntity>.unmodifiable(segment.points),
        )
        .toList(growable: false);
  }

  static WorkoutStatus _statusAt(
    DateTime timestamp,
    List<StatusChangeEvent> changes,
  ) {
    var status = WorkoutStatus.active;
    for (final change in changes) {
      if (change.timestamp.isAfter(timestamp)) break;
      status = change.status;
    }
    return status;
  }

  static bool _breaksAcceptedRouteBetween(
    DateTime previousTimestamp,
    DateTime currentTimestamp,
    List<StatusChangeEvent> changes,
  ) {
    return changes.any((change) {
      if (change.status == WorkoutStatus.active) {
        // A resumed point belongs to the new active segment, including when
        // its sample timestamp equals the resume boundary.
        return change.timestamp.isAfter(previousTimestamp) &&
            !change.timestamp.isAfter(currentTimestamp);
      }

      // A point at the pause/completion timestamp was accepted immediately
      // before that transition, so keep its incoming active line. The route
      // must break only after that boundary point.
      return !change.timestamp.isBefore(previousTimestamp) &&
          change.timestamp.isBefore(currentTimestamp);
    });
  }
}
