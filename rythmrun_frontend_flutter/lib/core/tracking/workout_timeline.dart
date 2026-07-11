enum WorkoutTimelinePhase { active, paused, completed }

class WorkoutTimelineSnapshot {
  final Duration wallDuration;
  final Duration pausedDuration;
  final Duration activeDuration;

  const WorkoutTimelineSnapshot({
    required this.wallDuration,
    required this.pausedDuration,
    required this.activeDuration,
  });
}

/// Immutable workout timing state.
///
/// Transition timestamps are made monotonic by clamping a timestamp that moves
/// backwards to [lastTransitionAt]. This keeps persisted workout durations
/// non-negative even when the device wall clock changes during a workout.
class WorkoutTimeline {
  final WorkoutTimelinePhase phase;
  final DateTime startedAt;
  final DateTime lastTransitionAt;
  final DateTime latestObservedAt;
  final DateTime? openPauseStartedAt;
  final Duration closedPausedDuration;
  final DateTime? completedAt;

  const WorkoutTimeline._({
    required this.phase,
    required this.startedAt,
    required this.lastTransitionAt,
    required this.latestObservedAt,
    required this.openPauseStartedAt,
    required this.closedPausedDuration,
    required this.completedAt,
  });

  factory WorkoutTimeline.start(DateTime at) {
    return WorkoutTimeline._(
      phase: WorkoutTimelinePhase.active,
      startedAt: at,
      lastTransitionAt: at,
      latestObservedAt: at,
      openPauseStartedAt: null,
      closedPausedDuration: Duration.zero,
      completedAt: null,
    );
  }

  /// Pauses an active workout. Pausing in any other phase is a no-op.
  WorkoutTimeline pause(DateTime at) {
    if (phase != WorkoutTimelinePhase.active) return this;

    final transitionAt = _clampToObservedBoundary(at);
    return WorkoutTimeline._(
      phase: WorkoutTimelinePhase.paused,
      startedAt: startedAt,
      lastTransitionAt: transitionAt,
      latestObservedAt: transitionAt,
      openPauseStartedAt: transitionAt,
      closedPausedDuration: closedPausedDuration,
      completedAt: null,
    );
  }

  /// Resumes a paused workout. Resuming in any other phase is a no-op.
  WorkoutTimeline resume(DateTime at) {
    if (phase != WorkoutTimelinePhase.paused) return this;

    final transitionAt = _clampToObservedBoundary(at);
    final pauseStartedAt = openPauseStartedAt ?? lastTransitionAt;
    final pauseDuration = _nonNegative(transitionAt.difference(pauseStartedAt));

    return WorkoutTimeline._(
      phase: WorkoutTimelinePhase.active,
      startedAt: startedAt,
      lastTransitionAt: transitionAt,
      latestObservedAt: transitionAt,
      openPauseStartedAt: null,
      closedPausedDuration: closedPausedDuration + pauseDuration,
      completedAt: null,
    );
  }

  /// Completes an active or paused workout.
  ///
  /// An open pause is closed at the completion timestamp. Completing an
  /// already-completed workout is a no-op, so that interval cannot be counted
  /// twice.
  WorkoutTimeline complete(DateTime at) {
    if (phase == WorkoutTimelinePhase.completed) return this;

    final transitionAt = _clampToObservedBoundary(at);
    final wallDuration = _nonNegative(transitionAt.difference(startedAt));
    var pausedDuration = closedPausedDuration;

    if (phase == WorkoutTimelinePhase.paused) {
      final pauseStartedAt = openPauseStartedAt ?? lastTransitionAt;
      pausedDuration += _nonNegative(transitionAt.difference(pauseStartedAt));
    }

    pausedDuration = _clampPausedDuration(pausedDuration, wallDuration);

    return WorkoutTimeline._(
      phase: WorkoutTimelinePhase.completed,
      startedAt: startedAt,
      lastTransitionAt: transitionAt,
      latestObservedAt: transitionAt,
      openPauseStartedAt: null,
      closedPausedDuration: pausedDuration,
      completedAt: transitionAt,
    );
  }

  /// Returns timing values at [at]. Completed timelines ignore [at] and keep
  /// the snapshot fixed at their completion boundary.
  WorkoutTimelineSnapshot snapshotAt(DateTime at) {
    final snapshotAt =
        phase == WorkoutTimelinePhase.completed
            ? completedAt ?? lastTransitionAt
            : _clampToObservedBoundary(at);
    final wallDuration = _nonNegative(snapshotAt.difference(startedAt));
    var pausedDuration = closedPausedDuration;

    if (phase == WorkoutTimelinePhase.paused) {
      final pauseStartedAt = openPauseStartedAt ?? lastTransitionAt;
      pausedDuration += _nonNegative(snapshotAt.difference(pauseStartedAt));
    }

    pausedDuration = _clampPausedDuration(pausedDuration, wallDuration);
    final activeDuration = _nonNegative(wallDuration - pausedDuration);

    return WorkoutTimelineSnapshot(
      wallDuration: wallDuration,
      pausedDuration: pausedDuration,
      activeDuration: activeDuration,
    );
  }

  /// Records a nondecreasing wall-clock observation without changing phase.
  WorkoutTimeline observe(DateTime at) {
    if (phase == WorkoutTimelinePhase.completed) return this;

    final observedAt = _clampToObservedBoundary(at);
    if (observedAt == latestObservedAt) return this;

    return WorkoutTimeline._(
      phase: phase,
      startedAt: startedAt,
      lastTransitionAt: lastTransitionAt,
      latestObservedAt: observedAt,
      openPauseStartedAt: openPauseStartedAt,
      closedPausedDuration: closedPausedDuration,
      completedAt: null,
    );
  }

  DateTime _clampToObservedBoundary(DateTime at) {
    if (at.isBefore(lastTransitionAt)) return lastTransitionAt;
    return at.isBefore(latestObservedAt) ? latestObservedAt : at;
  }

  static Duration _nonNegative(Duration duration) {
    return duration.isNegative ? Duration.zero : duration;
  }

  static Duration _clampPausedDuration(
    Duration pausedDuration,
    Duration wallDuration,
  ) {
    final nonNegativePause = _nonNegative(pausedDuration);
    return nonNegativePause > wallDuration ? wallDuration : nonNegativePause;
  }
}
