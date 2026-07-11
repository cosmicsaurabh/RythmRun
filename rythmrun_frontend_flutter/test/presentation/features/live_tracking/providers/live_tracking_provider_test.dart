import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/gps_point_acceptance_policy.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';

void main() {
  final start = DateTime.utc(2026, 7, 11, 10);

  group('LiveTrackingNotifier GPS and pause state machine', () {
    test(
      'paused movement and the first resumed point add no distance',
      () async {
        final context = _TestContext(start);
        await context.notifier.startWorkout(WorkoutType.running);

        final first = _point(seconds: 1, longitude: 77, speed: 1);
        final second = _point(
          seconds: 11,
          longitude: 77.0005,
          altitude: 10,
          speed: 4,
        );
        context.repository.emit(first);
        context.repository.emit(second);
        final distanceBeforePause =
            context.notifier.state.currentSession!.totalDistance;
        final paceBeforePause = context.notifier.state.currentPace;
        final maxSpeedBeforePause =
            context.notifier.state.currentSession!.maxSpeed;

        context.repository.currentTime = start.add(const Duration(seconds: 20));
        context.notifier.pauseWorkout();
        final pausedPoint = _point(
          seconds: 21,
          longitude: 77.1,
          altitude: 1000,
          speed: 9,
        );
        context.repository.emit(pausedPoint);

        expect(
          context.notifier.state.currentSession!.trackingPoints,
          <TrackingPointEntity>[first, second],
        );
        expect(
          context.notifier.state.currentSession!.totalDistance,
          distanceBeforePause,
        );
        expect(context.notifier.state.currentPace, paceBeforePause);
        expect(
          context.notifier.state.currentSession!.maxSpeed,
          maxSpeedBeforePause,
        );
        expect(context.notifier.state.currentLocation, pausedPoint);

        context.repository.currentTime = start.add(const Duration(seconds: 30));
        await context.notifier.resumeWorkout();
        context.repository.emit(
          _point(seconds: 25, longitude: 77.10005, speed: 1),
        );
        expect(
          context.notifier.state.currentSession!.trackingPoints,
          <TrackingPointEntity>[first, second],
        );

        final resumedAnchor = _point(
          seconds: 31,
          longitude: 77.1001,
          altitude: 1000,
          speed: 2,
        );
        context.repository.emit(resumedAnchor);
        expect(
          context.notifier.state.currentSession!.totalDistance,
          distanceBeforePause,
        );
        expect(context.notifier.state.currentPace, 0);

        final resumedMovement = _point(
          seconds: 41,
          longitude: 77.1005,
          altitude: 1010,
          speed: 3,
        );
        context.repository.emit(resumedMovement);

        final session = context.notifier.state.currentSession!;
        expect(session.trackingPoints, <TrackingPointEntity>[
          first,
          second,
          resumedAnchor,
          resumedMovement,
        ]);
        expect(session.totalDistance, greaterThan(distanceBeforePause));
        expect(session.totalDistance - distanceBeforePause, closeTo(43.5, 1));
        expect(session.maxSpeed, maxSpeedBeforePause);
        expect(context.repository.locationStreamReads, 1);
        expect(context.repository.hasLocationListener, isTrue);

        context.repository.currentTime = start.add(const Duration(seconds: 50));
        await context.notifier.stopWorkout();

        expect(context.repository.hasLocationListener, isFalse);
        expect(context.workoutRepository.saved, hasLength(1));
        final saved = context.workoutRepository.saved.single;
        expect(saved.trackingPoints, session.trackingPoints);
        expect(saved.elevationGain, closeTo(20, 0.001));
        await context.dispose();
      },
    );

    test(
      'finish while paused closes once and excludes shutdown latency',
      () async {
        final context = _TestContext(start);
        await context.notifier.startWorkout(WorkoutType.running);

        context.repository.currentTime = start.add(const Duration(seconds: 30));
        context.notifier.pauseWorkout();
        context.repository.currentTime = start.add(const Duration(seconds: 60));
        context.repository.onStop = () {
          context.repository.currentTime = start.add(
            const Duration(seconds: 80),
          );
        };

        await context.notifier.stopWorkout();
        await context.notifier.stopWorkout();

        expect(context.workoutRepository.saved, hasLength(1));
        final saved = context.workoutRepository.saved.single;
        expect(saved.endTime, start.add(const Duration(seconds: 60)));
        expect(saved.wallClockDuration, const Duration(seconds: 60));
        expect(saved.pausedDuration, const Duration(seconds: 30));
        expect(saved.activeDuration, const Duration(seconds: 30));
        expect(
          saved.statusChanges.map((event) => event.status),
          <WorkoutStatus>[
            WorkoutStatus.active,
            WorkoutStatus.paused,
            WorkoutStatus.completed,
          ],
        );
        expect(context.notifier.state.elapsedTime, const Duration(seconds: 30));
        await context.dispose();
      },
    );

    test('repeated pauses and the manual elapsed timer are exact', () async {
      final context = _TestContext(start);
      await context.notifier.startWorkout(WorkoutType.walking);

      context.repository.currentTime = start.add(const Duration(seconds: 10));
      context.timers.last.fire();
      expect(context.notifier.state.elapsedTime, const Duration(seconds: 10));

      context.notifier.pauseWorkout();
      final pausedTimer = context.timers.last;
      context.repository.currentTime = start.add(const Duration(seconds: 25));
      pausedTimer.fire();
      expect(context.notifier.state.elapsedTime, const Duration(seconds: 10));

      await context.notifier.resumeWorkout();
      context.repository.currentTime = start.add(const Duration(seconds: 40));
      context.notifier.pauseWorkout();
      context.repository.currentTime = start.add(const Duration(seconds: 50));
      await context.notifier.resumeWorkout();
      context.repository.currentTime = start.add(const Duration(seconds: 70));
      context.timers.last.fire();
      expect(context.notifier.state.elapsedTime, const Duration(seconds: 45));

      context.repository.currentTime = start.add(const Duration(seconds: 60));
      context.timers.last.fire();
      expect(context.notifier.state.elapsedTime, const Duration(seconds: 45));

      await context.notifier.stopWorkout();
      final saved = context.workoutRepository.saved.single;
      expect(saved.endTime, start.add(const Duration(seconds: 70)));
      expect(saved.pausedDuration, const Duration(seconds: 25));
      expect(saved.activeDuration, const Duration(seconds: 45));
      expect(saved.statusChanges.map((event) => event.status), <WorkoutStatus>[
        WorkoutStatus.active,
        WorkoutStatus.paused,
        WorkoutStatus.active,
        WorkoutStatus.paused,
        WorkoutStatus.active,
        WorkoutStatus.completed,
      ]);
      await context.dispose();
    });

    test(
      'rejected samples leave authoritative route and metrics unchanged',
      () async {
        final context = _TestContext(start);
        await context.notifier.startWorkout(WorkoutType.running);

        final accepted = _point(seconds: 1, longitude: 77);
        context.repository.emit(accepted);
        final before = context.notifier.state.currentSession!;

        context.repository.emit(_point(seconds: 2, longitude: 77.1));
        context.repository.emit(
          _point(seconds: 3, longitude: 77.0001, accuracy: 51),
        );
        context.repository.emit(_point(seconds: 0, longitude: 77.0001));
        context.repository.emit(_point(seconds: 4, latitude: double.nan));

        final after = context.notifier.state.currentSession!;
        expect(after.trackingPoints, <TrackingPointEntity>[accepted]);
        expect(after.totalDistance, before.totalDistance);
        expect(after.maxSpeed, before.maxSpeed);
        expect(context.notifier.state.currentPace, 0);
        await context.dispose();
      },
    );

    test(
      'serializes duplicate starts and invalidates a start reset in flight',
      () async {
        final context = _TestContext(start);
        final startCompleter = Completer<void>();
        context.repository.startCompleter = startCompleter;

        final firstStart = context.notifier.startWorkout(WorkoutType.running);
        final duplicateStart = context.notifier.startWorkout(
          WorkoutType.cycling,
        );
        await _flushAsyncWork();

        expect(context.repository.startCalls, 1);
        expect(context.repository.locationStreamReads, 1);
        expect(context.repository.maximumConcurrentListeners, 1);
        expect(context.notifier.state.currentSession, isNull);
        expect(context.notifier.state.isTracking, isFalse);

        final reset = context.notifier.resetWorkout();
        await reset;
        startCompleter.complete();
        await Future.wait(<Future<void>>[firstStart, duplicateStart]);
        await _flushAsyncWork();

        expect(context.notifier.state.currentSession, isNull);
        expect(context.notifier.state.isTracking, isFalse);
        expect(context.repository.hasLocationListener, isFalse);
        expect(context.repository.maximumConcurrentListeners, 1);
        await context.dispose();
      },
    );

    test('a delayed reset cannot overlap a new start', () async {
      final context = _TestContext(start);
      await context.notifier.startWorkout(WorkoutType.running);
      final activeTimer = context.timers.last;
      final stopCompleter = Completer<void>();
      context.repository.stopCompleter = stopCompleter;

      final pendingReset = context.notifier.resetWorkout();
      await _flushAsyncWork();
      context.repository.currentTime = start.add(const Duration(seconds: 20));
      activeTimer.fire();
      await context.notifier.startWorkout(WorkoutType.cycling);

      expect(activeTimer.isActive, isFalse);
      expect(context.notifier.state.elapsedTime, Duration.zero);
      expect(context.repository.startCalls, 1);
      expect(context.repository.locationStreamReads, 1);

      stopCompleter.complete();
      await pendingReset;
      expect(context.notifier.state.currentSession, isNull);

      await context.notifier.startWorkout(WorkoutType.cycling);
      expect(context.repository.startCalls, 2);
      expect(context.repository.maximumConcurrentListeners, 1);
      expect(context.notifier.state.currentSession!.type, WorkoutType.cycling);
      await context.notifier.stopWorkout();
      await context.dispose();
    });

    test(
      'dispose invalidates a pending start without publishing state',
      () async {
        final context = _TestContext(start);
        final startCompleter = Completer<void>();
        context.repository.startCompleter = startCompleter;

        final pendingStart = context.notifier.startWorkout(WorkoutType.running);
        await _flushAsyncWork();
        expect(context.repository.startCalls, 1);
        expect(context.repository.hasLocationListener, isTrue);

        context.notifier.dispose();
        startCompleter.complete();
        await pendingStart;
        await _flushAsyncWork();

        expect(context.repository.hasLocationListener, isFalse);
        expect(context.repository.maximumConcurrentListeners, 1);
        expect(context.workoutRepository.saved, isEmpty);
        await context.disposeRepositoryOnly();
      },
    );

    test('a late stream error cannot write state after dispose', () async {
      final context = _TestContext(start);
      await context.notifier.startWorkout(WorkoutType.running);
      context.repository.failCancellation = true;
      context.repository.failStop = true;

      context.notifier.dispose();
      await _flushAsyncWork();

      expect(context.repository.hasLocationListener, isTrue);
      expect(
        () => context.repository.emitError(StateError('simulated late error')),
        returnsNormally,
      );
      await context.disposeRepositoryOnly();
    });

    test(
      'cleanup failures do not strand finish or create two listeners',
      () async {
        final context = _TestContext(start);
        await context.notifier.startWorkout(WorkoutType.running);
        context.repository.failCancellation = true;
        context.repository.failStop = true;

        context.repository.currentTime = start.add(const Duration(seconds: 20));
        await context.notifier.stopWorkout();

        expect(context.workoutRepository.saved, hasLength(1));
        expect(
          context.notifier.state.currentSession!.status,
          WorkoutStatus.completed,
        );
        expect(context.repository.hasLocationListener, isTrue);
        expect(
          context.notifier.state.errorMessage,
          'Location tracking cleanup was incomplete.',
        );

        context.repository.failCancellation = false;
        context.repository.failStop = false;
        await context.notifier.startWorkout(WorkoutType.walking);

        expect(context.repository.startCalls, 2);
        expect(context.repository.hasLocationListener, isTrue);
        expect(context.repository.maximumConcurrentListeners, 1);
        expect(
          context.notifier.state.currentSession!.type,
          WorkoutType.walking,
        );
        await context.notifier.stopWorkout();
        await context.dispose();
      },
    );

    test('a pending save blocks a new workout from replacing it', () async {
      final context = _TestContext(start);
      await context.notifier.startWorkout(WorkoutType.running);
      final saveCompleter = Completer<void>();
      context.workoutRepository.saveCompleter = saveCompleter;

      final pendingStop = context.notifier.stopWorkout();
      await _flushAsyncWork();
      expect(context.workoutRepository.saved, hasLength(1));

      await context.notifier.startWorkout(WorkoutType.cycling);
      expect(context.repository.startCalls, 1);
      expect(context.notifier.state.currentSession!.type, WorkoutType.running);

      saveCompleter.complete();
      await pendingStop;
      await context.dispose();
    });

    test('a failed save remains visible and cannot be overwritten', () async {
      final context = _TestContext(start);
      await context.notifier.startWorkout(WorkoutType.running);
      context.workoutRepository.failSave = true;

      await context.notifier.stopWorkout();
      await context.notifier.startWorkout(WorkoutType.cycling);

      expect(context.workoutRepository.saved, hasLength(1));
      expect(context.repository.startCalls, 1);
      expect(context.notifier.state.currentSession!.type, WorkoutType.running);
      expect(
        context.notifier.state.errorMessage,
        'The previous workout is not saved yet. Keep this screen open.',
      );
      await context.notifier.resetWorkout();
      expect(context.notifier.state.currentSession!.type, WorkoutType.running);
      expect(
        context.notifier.state.errorMessage,
        'The previous workout could not be saved. Reset is blocked.',
      );
      await context.dispose();
    });
  });
}

class _TestContext {
  final _FakeLiveTrackingRepository repository;
  final _FakeWorkoutRepository workoutRepository;
  final List<_ManualTimer> timers = <_ManualTimer>[];
  late final LiveTrackingNotifier notifier;

  _TestContext(DateTime start)
    : repository = _FakeLiveTrackingRepository(start),
      workoutRepository = _FakeWorkoutRepository() {
    notifier = LiveTrackingNotifier(
      repository,
      workoutRepository,
      currentUserId: () => 7,
      periodicTimerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
  }

  Future<void> dispose() async {
    notifier.dispose();
    await _flushAsyncWork();
    await repository.dispose();
  }

  Future<void> disposeRepositoryOnly() async {
    await repository.dispose();
  }
}

class _FakeLiveTrackingRepository implements LiveTrackingRepository {
  final StreamController<TrackingPointEntity> _locations =
      StreamController<TrackingPointEntity>.broadcast(sync: true);
  late final _CountingStream<TrackingPointEntity> _countingStream =
      _CountingStream<TrackingPointEntity>(
        _locations.stream,
        shouldFailCancellation: () => failCancellation,
      );

  DateTime currentTime;
  int locationStreamReads = 0;
  int startCalls = 0;
  int stopCalls = 0;
  bool failCancellation = false;
  bool failStop = false;
  Completer<void>? startCompleter;
  Completer<void>? stopCompleter;
  void Function()? onStop;

  _FakeLiveTrackingRepository(this.currentTime);

  bool get hasLocationListener => _countingStream.activeListeners > 0;
  int get maximumConcurrentListeners =>
      _countingStream.maximumConcurrentListeners;

  void emit(TrackingPointEntity point) {
    _locations.add(point);
  }

  void emitError(Object error) {
    _locations.addError(error);
  }

  Future<void> dispose() async {
    await _locations.close();
  }

  @override
  Stream<TrackingPointEntity> get locationStream {
    locationStreamReads += 1;
    return _countingStream;
  }

  @override
  DateTime now() => currentTime;

  @override
  Future<LocationServiceStatus> checkPermissions() async {
    return LocationServiceStatus.granted;
  }

  @override
  Future<void> startTracking() async {
    startCalls += 1;
    await startCompleter?.future;
  }

  @override
  Future<void> stopTracking() async {
    stopCalls += 1;
    onStop?.call();
    await stopCompleter?.future;
    if (failStop) {
      throw StateError('simulated stop failure');
    }
  }

  @override
  Future<TrackingPointEntity?> getCurrentLocation() async => null;

  @override
  double calculateDistance(
    TrackingPointEntity point1,
    TrackingPointEntity point2,
  ) {
    return haversineTrackingDistanceMeters(point1, point2);
  }

  @override
  Future<double?> getCurrentElevation() async => null;

  @override
  Future<bool> requestLocationService() async => true;
}

class _FakeWorkoutRepository implements WorkoutRepository {
  final List<WorkoutSessionEntity> saved = <WorkoutSessionEntity>[];
  Completer<void>? saveCompleter;
  bool failSave = false;

  @override
  Future<int> saveWorkout(WorkoutSessionEntity workout) async {
    saved.add(workout);
    await saveCompleter?.future;
    if (failSave) {
      throw StateError('simulated save failure');
    }
    return saved.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManualTimer implements Timer {
  final void Function(Timer timer) _callback;
  bool _isActive = true;
  int _tick = 0;

  _ManualTimer(this._callback);

  void fire() {
    if (!_isActive) return;
    _tick += 1;
    _callback(this);
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _isActive = false;
  }
}

class _CountingStream<T> extends Stream<T> {
  final Stream<T> _source;
  final bool Function() _shouldFailCancellation;

  int activeListeners = 0;
  int maximumConcurrentListeners = 0;

  _CountingStream(
    this._source, {
    required bool Function() shouldFailCancellation,
  }) : _shouldFailCancellation = shouldFailCancellation;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    activeListeners += 1;
    if (activeListeners > maximumConcurrentListeners) {
      maximumConcurrentListeners = activeListeners;
    }
    final subscription = _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _CountingSubscription<T>(
      subscription,
      shouldFailCancellation: _shouldFailCancellation,
      onCancelled: () {
        activeListeners -= 1;
      },
    );
  }
}

class _CountingSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _delegate;
  final bool Function() _shouldFailCancellation;
  final void Function() _onCancelled;
  bool _cancelled = false;
  Future<void>? _cancelFuture;

  _CountingSubscription(
    this._delegate, {
    required bool Function() shouldFailCancellation,
    required void Function() onCancelled,
  }) : _shouldFailCancellation = shouldFailCancellation,
       _onCancelled = onCancelled;

  @override
  Future<void> cancel() {
    if (_cancelled) return Future<void>.value();
    final pendingCancellation = _cancelFuture;
    if (pendingCancellation != null) return pendingCancellation;
    if (_shouldFailCancellation()) {
      return Future<void>.error(StateError('simulated cancellation failure'));
    }
    final cancellation = _cancelDelegate();
    _cancelFuture = cancellation;
    return cancellation;
  }

  Future<void> _cancelDelegate() async {
    try {
      await _delegate.cancel();
      _cancelled = true;
      _onCancelled();
    } catch (_) {
      _cancelFuture = null;
      rethrow;
    }
  }

  @override
  void onData(void Function(T data)? handleData) {
    _delegate.onData(handleData);
  }

  @override
  void onError(Function? handleError) {
    _delegate.onError(handleError);
  }

  @override
  void onDone(void Function()? handleDone) {
    _delegate.onDone(handleDone);
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    _delegate.pause(resumeSignal);
  }

  @override
  void resume() {
    _delegate.resume();
  }

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return _delegate.asFuture<E>(futureValue);
  }
}

TrackingPointEntity _point({
  int seconds = 0,
  double latitude = 12,
  double longitude = 77,
  double altitude = 0,
  double accuracy = 5,
  double speed = 1,
}) {
  return TrackingPointEntity(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    accuracy: accuracy,
    speed: speed,
    heading: 90,
    timestamp: DateTime.utc(2026, 7, 11, 10).add(Duration(seconds: seconds)),
  );
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
