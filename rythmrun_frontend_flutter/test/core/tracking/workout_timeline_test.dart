import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/workout_timeline.dart';

void main() {
  final start = DateTime.utc(2026, 7, 11, 10);

  group('WorkoutTimeline', () {
    test('finish while paused closes the open pause exactly once', () {
      final active = WorkoutTimeline.start(start);
      final paused = active.pause(start.add(const Duration(seconds: 30)));
      final completed = paused.complete(start.add(const Duration(seconds: 60)));
      final snapshot = completed.snapshotAt(
        start.add(const Duration(hours: 1)),
      );

      expect(completed.phase, WorkoutTimelinePhase.completed);
      expect(completed.completedAt, start.add(const Duration(seconds: 60)));
      expect(snapshot.wallDuration, const Duration(seconds: 60));
      expect(snapshot.pausedDuration, const Duration(seconds: 30));
      expect(snapshot.activeDuration, const Duration(seconds: 30));

      final duplicateCompletion = completed.complete(
        start.add(const Duration(seconds: 90)),
      );
      expect(duplicateCompletion, same(completed));
      expect(
        duplicateCompletion.snapshotAt(start.add(const Duration(hours: 2))),
        isA<WorkoutTimelineSnapshot>()
            .having(
              (snapshot) => snapshot.wallDuration,
              'wall duration',
              const Duration(seconds: 60),
            )
            .having(
              (snapshot) => snapshot.pausedDuration,
              'paused duration',
              const Duration(seconds: 30),
            )
            .having(
              (snapshot) => snapshot.activeDuration,
              'active duration',
              const Duration(seconds: 30),
            ),
      );
    });

    test('completion adds one closed pause and one open pause', () {
      final completed = WorkoutTimeline.start(start)
          .pause(start.add(const Duration(seconds: 10)))
          .resume(start.add(const Duration(seconds: 20)))
          .pause(start.add(const Duration(seconds: 40)))
          .complete(start.add(const Duration(seconds: 70)));
      final snapshot = completed.snapshotAt(
        start.add(const Duration(seconds: 100)),
      );

      expect(snapshot.wallDuration, const Duration(seconds: 70));
      expect(snapshot.pausedDuration, const Duration(seconds: 40));
      expect(snapshot.activeDuration, const Duration(seconds: 30));
      expect(completed.openPauseStartedAt, isNull);
    });

    test('repeated pause and resume intervals produce exact duration', () {
      final completed = WorkoutTimeline.start(start)
          .pause(start.add(const Duration(seconds: 10)))
          .resume(start.add(const Duration(seconds: 25)))
          .pause(start.add(const Duration(seconds: 40)))
          .resume(start.add(const Duration(seconds: 50)))
          .complete(start.add(const Duration(seconds: 70)));
      final snapshot = completed.snapshotAt(
        start.add(const Duration(seconds: 70)),
      );

      expect(snapshot.wallDuration, const Duration(seconds: 70));
      expect(snapshot.pausedDuration, const Duration(seconds: 25));
      expect(snapshot.activeDuration, const Duration(seconds: 45));
      expect(completed.closedPausedDuration, const Duration(seconds: 25));
    });

    test('backward timestamps clamp and invalid transitions are no-ops', () {
      final active = WorkoutTimeline.start(start);

      expect(
        active.resume(start.add(const Duration(seconds: 1))),
        same(active),
      );

      final paused = active.pause(start.subtract(const Duration(minutes: 1)));
      expect(paused.phase, WorkoutTimelinePhase.paused);
      expect(paused.lastTransitionAt, start);
      expect(paused.openPauseStartedAt, start);
      expect(paused.pause(start.add(const Duration(seconds: 1))), same(paused));

      final resumed = paused.resume(start.subtract(const Duration(minutes: 2)));
      expect(resumed.phase, WorkoutTimelinePhase.active);
      expect(resumed.lastTransitionAt, start);
      expect(resumed.closedPausedDuration, Duration.zero);
      expect(
        resumed.resume(start.add(const Duration(seconds: 1))),
        same(resumed),
      );

      final completed = resumed.complete(
        start.subtract(const Duration(minutes: 3)),
      );
      final snapshot = completed.snapshotAt(
        start.subtract(const Duration(hours: 1)),
      );

      expect(completed.lastTransitionAt, start);
      expect(snapshot.wallDuration, Duration.zero);
      expect(snapshot.pausedDuration, Duration.zero);
      expect(snapshot.activeDuration, Duration.zero);
      expect(
        completed.pause(start.add(const Duration(seconds: 1))),
        same(completed),
      );
      expect(
        completed.resume(start.add(const Duration(seconds: 1))),
        same(completed),
      );

      final observed = WorkoutTimeline.start(
        start,
      ).observe(start.add(const Duration(seconds: 100)));
      final completedAfterClockRollback = observed.complete(
        start.add(const Duration(seconds: 50)),
      );
      expect(
        completedAfterClockRollback.completedAt,
        start.add(const Duration(seconds: 100)),
      );
      expect(
        completedAfterClockRollback
            .snapshotAt(start.add(const Duration(seconds: 50)))
            .activeDuration,
        const Duration(seconds: 100),
      );
    });
  });
}
