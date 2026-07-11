import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/gps_point_acceptance_policy.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

void main() {
  group('GPS point acceptance policy contract', () {
    test('commits the versioned MVP thresholds', () {
      expect(GpsPointAcceptancePolicy.policyVersion, 1);
      expect(GpsPointAcceptancePolicy.maximumHorizontalAccuracyMeters, 50);
      expect(
        GpsPointAcceptancePolicy.activeAnchorResetGap,
        const Duration(seconds: 30),
      );
      expect(GpsPointAcceptancePolicy.maximumSpeedFor(WorkoutType.running), 10);
      expect(GpsPointAcceptancePolicy.maximumSpeedFor(WorkoutType.walking), 5);
      expect(GpsPointAcceptancePolicy.maximumSpeedFor(WorkoutType.hiking), 5);
      expect(GpsPointAcceptancePolicy.maximumSpeedFor(WorkoutType.cycling), 30);
    });

    test('rejects non-finite optional and coordinate values', () {
      const policy = GpsPointAcceptancePolicy();
      final invalidPoints = <TrackingPointEntity>[
        _point(latitude: double.nan),
        _point(longitude: double.infinity),
        _point(altitude: double.negativeInfinity),
        _point(accuracy: double.nan),
        _point(speed: double.infinity),
        _point(heading: double.nan),
      ];

      for (final point in invalidPoints) {
        expect(
          _evaluate(policy, point).reason,
          GpsPointDecisionReason.rejectedNonFiniteValue,
        );
      }
    });

    test('rejects coordinate ranges and exactly the zero sentinel', () {
      const policy = GpsPointAcceptancePolicy();

      expect(
        _evaluate(policy, _point(latitude: 90.0001)).reason,
        GpsPointDecisionReason.rejectedCoordinateRange,
      );
      expect(
        _evaluate(policy, _point(longitude: -180.0001)).reason,
        GpsPointDecisionReason.rejectedCoordinateRange,
      );
      expect(
        _evaluate(policy, _point(latitude: 0, longitude: 0)).reason,
        GpsPointDecisionReason.rejectedZeroCoordinate,
      );
      final nearZero = _evaluate(
        policy,
        _point(latitude: 0.000001, longitude: 0.000001),
      );
      expect(nearZero.accepted, isTrue);
      expect(nearZero.canAdvanceActiveDistanceAnchor, isTrue);
      expect(nearZero.contributesActiveDistance, isFalse);
    });

    test('requires finite non-negative accuracy no greater than 50m', () {
      const policy = GpsPointAcceptancePolicy();

      expect(
        _evaluate(policy, _point(accuracy: null)).reason,
        GpsPointDecisionReason.rejectedMissingAccuracy,
      );
      expect(
        _evaluate(policy, _point(accuracy: -0.1)).reason,
        GpsPointDecisionReason.rejectedInvalidAccuracy,
      );
      expect(_evaluate(policy, _point(accuracy: 50)).accepted, isTrue);
      expect(
        _evaluate(policy, _point(accuracy: 50.0001)).reason,
        GpsPointDecisionReason.rejectedInaccurate,
      );
    });

    test('requires strictly increasing accepted timestamps', () {
      const policy = GpsPointAcceptancePolicy();
      final previous = _point(seconds: 10);

      expect(
        _evaluate(
          policy,
          _point(seconds: 10),
          previousAcceptedPoint: previous,
        ).reason,
        GpsPointDecisionReason.rejectedNonMonotonicTimestamp,
      );
      expect(
        _evaluate(
          policy,
          _point(seconds: 9),
          previousAcceptedPoint: previous,
        ).reason,
        GpsPointDecisionReason.rejectedNonMonotonicTimestamp,
      );
    });

    test('rejects a delayed paused sample after the resume boundary', () {
      const policy = GpsPointAcceptancePolicy();

      final decision = _evaluate(
        policy,
        _point(seconds: 25),
        previousAcceptedPoint: _point(seconds: 20),
        activeSegmentStartedAt: _time(30),
      );

      expect(decision.accepted, isFalse);
      expect(
        decision.reason,
        GpsPointDecisionReason.rejectedBeforeActiveBoundary,
      );
    });

    test('bounds optional reported speed for every workout type', () {
      const policy = GpsPointAcceptancePolicy();

      for (final type in WorkoutType.values) {
        final maximum = GpsPointAcceptancePolicy.maximumSpeedFor(type);
        expect(
          _evaluate(policy, _point(speed: maximum), type: type).accepted,
          isTrue,
        );
        expect(
          _evaluate(policy, _point(speed: maximum + 0.001), type: type).reason,
          GpsPointDecisionReason.rejectedReportedSpeed,
        );
      }
    });

    test('enforces exact implied-speed ceilings for every workout type', () {
      for (final type in WorkoutType.values) {
        final maximum = GpsPointAcceptancePolicy.maximumSpeedFor(type);
        var distance = maximum * 10;
        final policy = GpsPointAcceptancePolicy(
          distanceBetween: (_, _) => distance,
        );
        final anchor = _point(seconds: 0);

        final atLimit = _evaluate(
          policy,
          _point(seconds: 10),
          type: type,
          previousAcceptedPoint: anchor,
          activeDistanceAnchor: anchor,
        );
        expect(atLimit.accepted, isTrue);
        expect(atLimit.canAdvanceActiveDistanceAnchor, isTrue);
        expect(atLimit.contributesActiveDistance, isTrue);
        expect(atLimit.impliedSpeedMetersPerSecond, maximum);

        distance = maximum * 10 + 0.01;
        final overLimit = _evaluate(
          policy,
          _point(seconds: 10),
          type: type,
          previousAcceptedPoint: anchor,
          activeDistanceAnchor: anchor,
        );
        expect(overLimit.accepted, isFalse);
        expect(overLimit.reason, GpsPointDecisionReason.rejectedImpliedSpeed);
      }
    });

    test('advances at 30 seconds and resets after 30 seconds', () {
      var distance = 300.0;
      final policy = GpsPointAcceptancePolicy(
        distanceBetween: (_, _) => distance,
      );
      final anchor = _point(seconds: 0);

      final atBoundary = _evaluate(
        policy,
        _point(seconds: 30),
        previousAcceptedPoint: anchor,
        activeDistanceAnchor: anchor,
      );
      expect(atBoundary.canAdvanceActiveDistanceAnchor, isTrue);
      expect(atBoundary.contributesActiveDistance, isTrue);
      expect(atBoundary.startsNewActiveSegment, isFalse);

      distance = 100000;
      final afterBoundary = _evaluate(
        policy,
        _point(seconds: 31),
        previousAcceptedPoint: anchor,
        activeDistanceAnchor: anchor,
      );
      expect(afterBoundary.accepted, isTrue);
      expect(afterBoundary.canAdvanceActiveDistanceAnchor, isTrue);
      expect(afterBoundary.contributesActiveDistance, isFalse);
      expect(afterBoundary.startsNewActiveSegment, isTrue);
      expect(
        afterBoundary.reason,
        GpsPointDecisionReason.acceptedAfterSampleGap,
      );
    });

    test('keeps the last accepted anchor after rejecting a jump', () {
      final anchor = _point(seconds: 0, longitude: 77);
      final rejectedJump = _point(seconds: 10, longitude: 78);
      final validAfterJump = _point(seconds: 20, longitude: 77.0001);
      final policy = GpsPointAcceptancePolicy(
        distanceBetween:
            (_, second) => identical(second, rejectedJump) ? 1000 : 10,
      );

      final rejected = _evaluate(
        policy,
        rejectedJump,
        previousAcceptedPoint: anchor,
        activeDistanceAnchor: anchor,
      );
      expect(rejected.accepted, isFalse);

      final accepted = _evaluate(
        policy,
        validAfterJump,
        previousAcceptedPoint: anchor,
        activeDistanceAnchor: anchor,
      );
      expect(accepted.accepted, isTrue);
      expect(accepted.distanceDeltaMeters, 10);
    });

    test('paused samples can update only the accepted marker', () {
      const policy = GpsPointAcceptancePolicy();
      final previous = _point(seconds: 0);

      final decision = policy.evaluate(
        point: _point(seconds: 1, longitude: 120),
        workoutType: WorkoutType.running,
        isWorkoutActive: false,
        previousAcceptedPoint: previous,
        activeDistanceAnchor: previous,
      );

      expect(decision.accepted, isTrue);
      expect(decision.reason, GpsPointDecisionReason.acceptedPausedMarker);
      expect(decision.canAdvanceActiveDistanceAnchor, isFalse);
      expect(decision.contributesActiveDistance, isFalse);
      expect(decision.startsNewActiveSegment, isFalse);
      expect(decision.distanceDeltaMeters, 0);
    });

    test('haversine helper returns a stable short-distance result', () {
      final distance = haversineTrackingDistanceMeters(
        _point(latitude: 12, longitude: 77),
        _point(latitude: 12.001, longitude: 77),
      );

      expect(distance, closeTo(111.2, 0.2));
    });
  });
}

GpsPointAcceptanceDecision _evaluate(
  GpsPointAcceptancePolicy policy,
  TrackingPointEntity point, {
  WorkoutType type = WorkoutType.running,
  TrackingPointEntity? previousAcceptedPoint,
  TrackingPointEntity? activeDistanceAnchor,
  DateTime? activeSegmentStartedAt,
}) {
  return policy.evaluate(
    point: point,
    workoutType: type,
    isWorkoutActive: true,
    previousAcceptedPoint: previousAcceptedPoint,
    activeDistanceAnchor: activeDistanceAnchor,
    activeSegmentStartedAt: activeSegmentStartedAt,
  );
}

TrackingPointEntity _point({
  double latitude = 12,
  double longitude = 77,
  double? altitude = 10,
  double? accuracy = 5,
  double? speed = 1,
  double? heading = 90,
  int seconds = 0,
}) {
  return TrackingPointEntity(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    accuracy: accuracy,
    speed: speed,
    heading: heading,
    timestamp: _time(seconds),
  );
}

DateTime _time(int seconds) =>
    DateTime.utc(2026, 7, 11, 10).add(Duration(seconds: seconds));
