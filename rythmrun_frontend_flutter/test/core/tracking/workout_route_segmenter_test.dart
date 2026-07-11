import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/workout_route_segmenter.dart';
import 'package:rythmrun_frontend_flutter/core/utils/calculation_helper.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

void main() {
  group('WorkoutRouteSegmenter', () {
    test('splits a version-2 route across pause and resume', () {
      final points = <TrackingPointEntity>[
        _point(0),
        _point(10),
        _point(40),
        _point(50),
      ];
      final session = _session(
        points: points,
        statusChanges: <StatusChangeEvent>[
          _status(WorkoutStatus.active, 0),
          _status(WorkoutStatus.paused, 15),
          _status(WorkoutStatus.active, 30),
          _status(WorkoutStatus.completed, 60),
        ],
      );

      final segments = WorkoutRouteSegmenter.buildSegments(session);

      expect(segments, hasLength(2));
      expect(segments.map((segment) => segment.status), <WorkoutStatus>[
        WorkoutStatus.active,
        WorkoutStatus.active,
      ]);
      expect(segments.first.points, points.take(2));
      expect(segments.last.points, points.skip(2));
      expect(segments.expand((segment) => segment.points).toList(), points);

      final boundaryPoints = <TrackingPointEntity>[
        _point(0, altitude: 0),
        _point(15, altitude: 10),
        _point(30, altitude: 100),
        _point(60, altitude: 110),
      ];
      final boundarySegments = WorkoutRouteSegmenter.buildSegments(
        _session(
          points: boundaryPoints,
          statusChanges: <StatusChangeEvent>[
            _status(WorkoutStatus.active, 0),
            _status(WorkoutStatus.paused, 15),
            _status(WorkoutStatus.active, 30),
            _status(WorkoutStatus.completed, 60),
          ],
        ),
      );
      expect(
        boundarySegments.map((segment) => segment.status),
        everyElement(WorkoutStatus.active),
      );
      expect(boundarySegments, hasLength(2));
      expect(boundarySegments.first.points, boundaryPoints.take(2));
      expect(boundarySegments.last.points, boundaryPoints.skip(2));
      expect(
        boundarySegments.expand((segment) => segment.points).toList(),
        boundaryPoints,
      );
      expect(
        calculateSegmentedElevationData(
          WorkoutRouteSegmenter.buildActivePointSegments(
            _session(
              points: boundaryPoints,
              statusChanges: <StatusChangeEvent>[
                _status(WorkoutStatus.active, 0),
                _status(WorkoutStatus.paused, 15),
                _status(WorkoutStatus.active, 30),
                _status(WorkoutStatus.completed, 60),
              ],
            ),
          ),
        ).gain,
        20,
      );
    });

    test('splits only gaps strictly over 30 seconds for version 2', () {
      final exactBoundary = _session(
        points: <TrackingPointEntity>[_point(0), _point(30)],
      );
      final overBoundary = _session(
        points: <TrackingPointEntity>[
          _point(0),
          _point(10),
          _point(41),
          _point(50),
        ],
      );

      expect(WorkoutRouteSegmenter.buildSegments(exactBoundary), hasLength(1));
      final segments = WorkoutRouteSegmenter.buildSegments(overBoundary);
      expect(segments, hasLength(2));
      expect(segments.first.points, overBoundary.trackingPoints.take(2));
      expect(segments.last.points, overBoundary.trackingPoints.skip(2));
    });

    test('keeps legacy gap behavior explicit and unchanged', () {
      final legacy = _session(
        metricsVersion: WorkoutSessionEntity.legacyMetricsVersion,
        points: <TrackingPointEntity>[_point(0), _point(60)],
      );

      final segments = WorkoutRouteSegmenter.buildSegments(legacy);

      expect(segments, hasLength(1));
      expect(segments.single.points, legacy.trackingPoints);
    });

    test('preserves legacy paused samples as dashed segments', () {
      final points = <TrackingPointEntity>[
        _point(0),
        _point(20),
        _point(25),
        _point(40),
      ];
      final legacy = _session(
        metricsVersion: WorkoutSessionEntity.legacyMetricsVersion,
        points: points,
        statusChanges: <StatusChangeEvent>[
          _status(WorkoutStatus.active, 0),
          _status(WorkoutStatus.paused, 15),
          _status(WorkoutStatus.active, 35),
        ],
      );

      final segments = WorkoutRouteSegmenter.buildSegments(legacy);

      expect(segments.map((segment) => segment.status), <WorkoutStatus>[
        WorkoutStatus.active,
        WorkoutStatus.paused,
        WorkoutStatus.active,
      ]);
      expect(segments.expand((segment) => segment.points).toList(), points);
    });
  });
}

WorkoutSessionEntity _session({
  int metricsVersion = WorkoutSessionEntity.currentMetricsVersion,
  required List<TrackingPointEntity> points,
  List<StatusChangeEvent>? statusChanges,
}) {
  return WorkoutSessionEntity(
    clientSyncId: 'route-segment-test',
    metricsVersion: metricsVersion,
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    startTime: _time(0),
    endTime: _time(70),
    trackingPoints: points,
    statusChanges:
        statusChanges ?? <StatusChangeEvent>[_status(WorkoutStatus.active, 0)],
    userId: 1,
  );
}

TrackingPointEntity _point(int seconds, {double? altitude}) {
  return TrackingPointEntity(
    latitude: 12,
    longitude: 77 + seconds / 100000,
    altitude: altitude,
    accuracy: 5,
    speed: 1,
    timestamp: _time(seconds),
  );
}

StatusChangeEvent _status(WorkoutStatus status, int seconds) {
  return StatusChangeEvent(status: status, timestamp: _time(seconds));
}

DateTime _time(int seconds) =>
    DateTime.utc(2026, 7, 11, 10).add(Duration(seconds: seconds));
