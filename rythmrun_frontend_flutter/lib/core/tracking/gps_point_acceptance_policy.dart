import 'dart:math' as math;

import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

typedef TrackingDistanceCalculator =
    double Function(TrackingPointEntity first, TrackingPointEntity second);

enum GpsPointDecisionReason {
  acceptedActiveSample,
  acceptedActiveAnchor,
  acceptedAfterSampleGap,
  acceptedPausedMarker,
  rejectedNonFiniteValue,
  rejectedCoordinateRange,
  rejectedZeroCoordinate,
  rejectedMissingAccuracy,
  rejectedInvalidAccuracy,
  rejectedInaccurate,
  rejectedNonMonotonicTimestamp,
  rejectedBeforeActiveBoundary,
  rejectedReportedSpeed,
  rejectedImpliedSpeed,
}

class GpsPointAcceptanceDecision {
  final bool accepted;
  final GpsPointDecisionReason reason;
  final bool canAdvanceActiveDistanceAnchor;
  final bool contributesActiveDistance;
  final bool startsNewActiveSegment;
  final double distanceDeltaMeters;
  final Duration? timestampDelta;
  final double? impliedSpeedMetersPerSecond;

  const GpsPointAcceptanceDecision._({
    required this.accepted,
    required this.reason,
    this.canAdvanceActiveDistanceAnchor = false,
    this.contributesActiveDistance = false,
    this.startsNewActiveSegment = false,
    this.distanceDeltaMeters = 0,
    this.timestampDelta,
    this.impliedSpeedMetersPerSecond,
  });

  const GpsPointAcceptanceDecision.rejected(
    GpsPointDecisionReason reason, {
    Duration? timestampDelta,
    double? impliedSpeedMetersPerSecond,
  }) : this._(
         accepted: false,
         reason: reason,
         timestampDelta: timestampDelta,
         impliedSpeedMetersPerSecond: impliedSpeedMetersPerSecond,
       );

  const GpsPointAcceptanceDecision.accepted({
    required GpsPointDecisionReason reason,
    required bool canAdvanceActiveDistanceAnchor,
    required bool contributesActiveDistance,
    required bool startsNewActiveSegment,
    double distanceDeltaMeters = 0,
    Duration? timestampDelta,
    double? impliedSpeedMetersPerSecond,
  }) : this._(
         accepted: true,
         reason: reason,
         canAdvanceActiveDistanceAnchor: canAdvanceActiveDistanceAnchor,
         contributesActiveDistance: contributesActiveDistance,
         startsNewActiveSegment: startsNewActiveSegment,
         distanceDeltaMeters: distanceDeltaMeters,
         timestampDelta: timestampDelta,
         impliedSpeedMetersPerSecond: impliedSpeedMetersPerSecond,
       );
}

/// Versioned, pure policy for deciding which raw GPS samples are authoritative.
///
/// The initial ceilings are deliberately conservative for the early MVP: they
/// reject common urban GPS spikes without pretending to be sport-performance
/// limits. Changing them requires fixture/device evidence and a policy-version
/// increment because accepted points affect persisted routes and metrics.
class GpsPointAcceptancePolicy {
  static const int policyVersion = 1;
  static const double maximumHorizontalAccuracyMeters = 50;
  static const Duration activeAnchorResetGap = Duration(seconds: 30);
  static const double maximumRunningSpeedMetersPerSecond = 10;
  static const double maximumWalkingSpeedMetersPerSecond = 5;
  static const double maximumHikingSpeedMetersPerSecond = 5;
  static const double maximumCyclingSpeedMetersPerSecond = 30;

  final TrackingDistanceCalculator _distanceBetween;

  const GpsPointAcceptancePolicy({
    TrackingDistanceCalculator distanceBetween =
        haversineTrackingDistanceMeters,
  }) : _distanceBetween = distanceBetween;

  GpsPointAcceptanceDecision evaluate({
    required TrackingPointEntity point,
    required WorkoutType workoutType,
    required bool isWorkoutActive,
    TrackingPointEntity? previousAcceptedPoint,
    TrackingPointEntity? activeDistanceAnchor,
    DateTime? activeSegmentStartedAt,
  }) {
    if (!_hasOnlyFiniteValues(point)) {
      return const GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedNonFiniteValue,
      );
    }

    if (point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      return const GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedCoordinateRange,
      );
    }

    if (point.latitude == 0 && point.longitude == 0) {
      return const GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedZeroCoordinate,
      );
    }

    final accuracy = point.accuracy;
    if (accuracy == null) {
      return const GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedMissingAccuracy,
      );
    }
    if (accuracy < 0) {
      return const GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedInvalidAccuracy,
      );
    }
    if (accuracy > maximumHorizontalAccuracyMeters) {
      return const GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedInaccurate,
      );
    }

    Duration? acceptedPointDelta;
    if (previousAcceptedPoint != null) {
      acceptedPointDelta = point.timestamp.difference(
        previousAcceptedPoint.timestamp,
      );
      if (acceptedPointDelta <= Duration.zero) {
        return GpsPointAcceptanceDecision.rejected(
          GpsPointDecisionReason.rejectedNonMonotonicTimestamp,
          timestampDelta: acceptedPointDelta,
        );
      }
    }

    if (isWorkoutActive &&
        activeSegmentStartedAt != null &&
        point.timestamp.isBefore(activeSegmentStartedAt)) {
      return GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedBeforeActiveBoundary,
        timestampDelta: acceptedPointDelta,
      );
    }

    final maximumSpeed = maximumSpeedFor(workoutType);
    final reportedSpeed = point.speed;
    if (reportedSpeed != null &&
        (reportedSpeed < 0 || reportedSpeed > maximumSpeed)) {
      return GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedReportedSpeed,
        timestampDelta: acceptedPointDelta,
      );
    }

    if (!isWorkoutActive) {
      return GpsPointAcceptanceDecision.accepted(
        reason: GpsPointDecisionReason.acceptedPausedMarker,
        canAdvanceActiveDistanceAnchor: false,
        contributesActiveDistance: false,
        startsNewActiveSegment: false,
        timestampDelta: acceptedPointDelta,
      );
    }

    if (activeDistanceAnchor == null) {
      return GpsPointAcceptanceDecision.accepted(
        reason: GpsPointDecisionReason.acceptedActiveAnchor,
        canAdvanceActiveDistanceAnchor: true,
        contributesActiveDistance: false,
        startsNewActiveSegment: true,
        timestampDelta: acceptedPointDelta,
      );
    }

    final anchorDelta = point.timestamp.difference(
      activeDistanceAnchor.timestamp,
    );
    if (anchorDelta <= Duration.zero) {
      return GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedNonMonotonicTimestamp,
        timestampDelta: anchorDelta,
      );
    }

    if (anchorDelta > activeAnchorResetGap) {
      return GpsPointAcceptanceDecision.accepted(
        reason: GpsPointDecisionReason.acceptedAfterSampleGap,
        canAdvanceActiveDistanceAnchor: true,
        contributesActiveDistance: false,
        startsNewActiveSegment: true,
        timestampDelta: anchorDelta,
      );
    }

    final distanceMeters = _distanceBetween(activeDistanceAnchor, point);
    if (!distanceMeters.isFinite || distanceMeters < 0) {
      return GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedNonFiniteValue,
        timestampDelta: anchorDelta,
      );
    }

    final impliedSpeed =
        distanceMeters /
        (anchorDelta.inMicroseconds / Duration.microsecondsPerSecond);
    if (!impliedSpeed.isFinite || impliedSpeed > maximumSpeed) {
      return GpsPointAcceptanceDecision.rejected(
        GpsPointDecisionReason.rejectedImpliedSpeed,
        timestampDelta: anchorDelta,
        impliedSpeedMetersPerSecond: impliedSpeed,
      );
    }

    return GpsPointAcceptanceDecision.accepted(
      reason: GpsPointDecisionReason.acceptedActiveSample,
      canAdvanceActiveDistanceAnchor: true,
      contributesActiveDistance: true,
      startsNewActiveSegment: false,
      distanceDeltaMeters: distanceMeters,
      timestampDelta: anchorDelta,
      impliedSpeedMetersPerSecond: impliedSpeed,
    );
  }

  static double maximumSpeedFor(WorkoutType type) {
    switch (type) {
      case WorkoutType.running:
        return maximumRunningSpeedMetersPerSecond;
      case WorkoutType.walking:
        return maximumWalkingSpeedMetersPerSecond;
      case WorkoutType.hiking:
        return maximumHikingSpeedMetersPerSecond;
      case WorkoutType.cycling:
        return maximumCyclingSpeedMetersPerSecond;
    }
  }

  bool _hasOnlyFiniteValues(TrackingPointEntity point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        (point.altitude?.isFinite ?? true) &&
        (point.accuracy?.isFinite ?? true) &&
        (point.speed?.isFinite ?? true) &&
        (point.heading?.isFinite ?? true);
  }
}

double haversineTrackingDistanceMeters(
  TrackingPointEntity first,
  TrackingPointEntity second,
) {
  const earthRadiusMeters = 6371000.0;
  final firstLatitudeRadians = first.latitude * math.pi / 180;
  final secondLatitudeRadians = second.latitude * math.pi / 180;
  final latitudeDeltaRadians =
      (second.latitude - first.latitude) * math.pi / 180;
  final longitudeDeltaRadians =
      (second.longitude - first.longitude) * math.pi / 180;

  final haversine =
      math.sin(latitudeDeltaRadians / 2) * math.sin(latitudeDeltaRadians / 2) +
      math.cos(firstLatitudeRadians) *
          math.cos(secondLatitudeRadians) *
          math.sin(longitudeDeltaRadians / 2) *
          math.sin(longitudeDeltaRadians / 2);
  final clampedHaversine = haversine.clamp(0.0, 1.0);
  final angularDistance =
      2 *
      math.atan2(math.sqrt(clampedHaversine), math.sqrt(1 - clampedHaversine));

  return earthRadiusMeters * angularDistance;
}
