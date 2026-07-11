import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/gps_point_acceptance_policy.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/workout_route_segmenter.dart';
import 'package:rythmrun_frontend_flutter/core/tracking/workout_timeline.dart';
import 'package:rythmrun_frontend_flutter/core/utils/calculation_helper.dart';
import 'package:rythmrun_frontend_flutter/core/utils/client_sync_id_generator.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';

typedef PeriodicTimerFactory =
    Timer Function(Duration duration, void Function(Timer timer) callback);

Future<void> _noopWorkoutAdded() async {}

enum LiveWorkoutFinalizationStatus {
  noActiveWorkout,
  saved,
  savePending,
  failed,
}

class LiveWorkoutFinalizationResult {
  final LiveWorkoutFinalizationStatus status;

  const LiveWorkoutFinalizationResult(this.status);

  bool get isDurablySaved =>
      status == LiveWorkoutFinalizationStatus.saved ||
      status == LiveWorkoutFinalizationStatus.noActiveWorkout;
}

class LiveTrackingNotifier extends StateNotifier<LiveTrackingState> {
  final LiveTrackingRepository _liveTrackingRepository;
  final WorkoutRepository _workoutRepository;
  final int? Function() _currentUserId;
  final Future<void> Function() _onWorkoutAdded;
  final GpsPointAcceptancePolicy _pointAcceptancePolicy;
  final PeriodicTimerFactory _periodicTimerFactory;

  StreamSubscription<TrackingPointEntity>? _locationSubscription;
  Timer? _elapsedTimer;
  WorkoutTimeline? _timeline;
  TrackingPointEntity? _lastAcceptedPoint;
  TrackingPointEntity? _activeDistanceAnchor;
  DateTime? _activeSegmentStartedAt;
  WorkoutSessionEntity? _unsavedCompletedWorkout;
  int _operationGeneration = 0;
  bool _isStarting = false;
  bool _isStopping = false;
  bool _isResetting = false;
  bool _cleanupRequired = false;
  bool _isAccountExitQuiescing = false;
  bool _isDisposed = false;
  Future<void>? _startFuture;
  Future<LiveWorkoutFinalizationResult>? _stopFuture;

  LiveTrackingNotifier(
    this._liveTrackingRepository,
    this._workoutRepository, {
    required int? Function() currentUserId,
    Future<void> Function()? onWorkoutAdded,
    GpsPointAcceptancePolicy pointAcceptancePolicy =
        const GpsPointAcceptancePolicy(),
    PeriodicTimerFactory periodicTimerFactory = Timer.periodic,
  }) : _currentUserId = currentUserId,
       _onWorkoutAdded = onWorkoutAdded ?? _noopWorkoutAdded,
       _pointAcceptancePolicy = pointAcceptancePolicy,
       _periodicTimerFactory = periodicTimerFactory,
       super(const LiveTrackingState());

  void clearErrorMessage() {
    if (_isDisposed) return;
    state = state.copyWith(errorMessage: null);
  }

  /// Check location permissions
  Future<void> checkPermissions() async {
    if (_isDisposed) return;
    try {
      state = state.copyWith(isLoading: true);
      LocationServiceStatus permissionStatus =
          await _liveTrackingRepository.checkPermissions();
      if (_isDisposed) return;

      bool hasPermission = LocationErrorHandler.isLocationServicesEnabled(
        permissionStatus,
      );
      String? errorMessage;

      if (!hasPermission) {
        errorMessage = LocationErrorHandler.getLocationErrorMessage(
          permissionStatus,
        );
      }

      state = state.copyWith(
        hasLocationPermission: hasPermission,
        isLoading: false,
        errorMessage: errorMessage,
        locationServiceStatus: permissionStatus,
      );
    } catch (_) {
      if (_isDisposed) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to check location permissions.',
        hasLocationPermission: false,
        locationServiceStatus: LocationServiceStatus.permissionDenied,
      );
    }
  }

  /// Request location service to be enabled (shows system dialog on Android)
  /// After requesting, re-checks permissions to update state
  Future<void> requestLocationService() async {
    if (_isDisposed) return;
    try {
      state = state.copyWith(isLoading: true);
      final serviceEnabled =
          await _liveTrackingRepository.requestLocationService();
      if (_isDisposed) return;

      // Re-check permissions after requesting service
      // This will update the state with the new permission status
      await checkPermissions();

      if (serviceEnabled) return;
    } catch (_) {
      if (_isDisposed) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to request location service.',
      );
    }
  }

  /// Start a new workout session
  Future<void> startWorkout(WorkoutType type) {
    if (_isAccountExitQuiescing) return Future<void>.value();
    final pendingStart = _startFuture;
    if (pendingStart != null) return pendingStart;

    late final Future<void> trackedStart;
    trackedStart = _startWorkoutOnce(type).whenComplete(() {
      if (identical(_startFuture, trackedStart)) {
        _startFuture = null;
      }
    });
    _startFuture = trackedStart;
    return trackedStart;
  }

  Future<void> _startWorkoutOnce(WorkoutType type) async {
    if (_isDisposed ||
        _isAccountExitQuiescing ||
        _isStarting ||
        _isStopping ||
        _isResetting ||
        _unsavedCompletedWorkout != null ||
        (state.currentSession != null &&
            state.currentSession!.status != WorkoutStatus.completed)) {
      if (_unsavedCompletedWorkout != null && !_isDisposed) {
        state = state.copyWith(
          errorMessage:
              'The previous workout is not saved yet. Keep this screen open.',
        );
      }
      return;
    }

    _isStarting = true;
    final operationGeneration = ++_operationGeneration;
    StreamSubscription<TrackingPointEntity>? pendingSubscription;

    try {
      state = state.copyWith(isLoading: true, errorMessage: null);

      if (_cleanupRequired) {
        final cleanupSucceeded = await _retryRequiredCleanup();
        if (!_isOperationCurrent(operationGeneration)) return;
        if (!cleanupSucceeded) {
          state = state.copyWith(
            isLoading: false,
            errorMessage:
                'Location tracking cleanup is still pending. Please retry.',
          );
          return;
        }
      }

      if (!state.hasLocationPermission) {
        final permissionStatus =
            await _liveTrackingRepository.checkPermissions();
        if (!_isOperationCurrent(operationGeneration)) return;
        final hasPermission = LocationErrorHandler.isLocationServicesEnabled(
          permissionStatus,
        );
        state = state.copyWith(
          hasLocationPermission: hasPermission,
          locationServiceStatus: permissionStatus,
        );
        if (!hasPermission) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: LocationErrorHandler.getLocationErrorMessage(
              permissionStatus,
            ),
          );
          return;
        }
      }

      final userId = _currentUserId();
      if (userId == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'User not authenticated',
        );
        return;
      }

      final startTime = _liveTrackingRepository.now();
      final timeline = WorkoutTimeline.start(startTime);
      final initialStatusChange = StatusChangeEvent(
        status: WorkoutStatus.active,
        timestamp: startTime,
      );

      // Create new workout session
      final newSession = WorkoutSessionEntity(
        clientSyncId: ClientSyncIdGenerator.generate(
          startTime: startTime,
          userId: userId,
        ),
        type: type,
        status: WorkoutStatus.active,
        startTime: startTime,
        statusChanges: [initialStatusChange],
        userId: userId,
      );

      pendingSubscription = _liveTrackingRepository.locationStream.listen(
        _onLocationUpdate,
        onError: _onLocationError,
      );
      _locationSubscription = pendingSubscription;
      await _liveTrackingRepository.startTracking();
      if (!_isOperationCurrent(operationGeneration)) {
        await _cleanupTrackingResources(pendingSubscription);
        return;
      }

      _timeline = timeline;
      _lastAcceptedPoint = null;
      _activeDistanceAnchor = null;
      _activeSegmentStartedAt = startTime;
      state = state.copyWith(
        currentSession: newSession,
        currentLocation: null,
        isTracking: true,
        isLoading: false,
        elapsedTime: Duration.zero,
        currentPace: 0,
      );
      _startElapsedTimer();
    } catch (_) {
      await _cleanupTrackingResources(pendingSubscription);
      _resetInternalTrackingState();
      if (_isOperationCurrent(operationGeneration)) {
        state = LiveTrackingState(
          isLoading: false,
          errorMessage: 'Failed to start workout. Please try again.',
          hasLocationPermission: state.hasLocationPermission,
          locationServiceStatus: state.locationServiceStatus,
        );
      }
    } finally {
      _isStarting = false;
    }
  }

  /// Pause the current workout
  void pauseWorkout() {
    final session = state.currentSession;
    final timeline = _timeline;
    if (_isDisposed ||
        _isAccountExitQuiescing ||
        _isStarting ||
        _isStopping ||
        _isResetting ||
        session == null ||
        session.status != WorkoutStatus.active ||
        timeline == null ||
        timeline.phase != WorkoutTimelinePhase.active) {
      return;
    }

    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    final pausedTimeline = timeline.pause(_liveTrackingRepository.now());
    _timeline = pausedTimeline;
    _activeDistanceAnchor = null;
    _activeSegmentStartedAt = null;
    final pauseStatusChange = StatusChangeEvent(
      status: WorkoutStatus.paused,
      timestamp: pausedTimeline.lastTransitionAt,
    );
    final snapshot = pausedTimeline.snapshotAt(pausedTimeline.lastTransitionAt);

    state = state.copyWith(
      currentSession: session.copyWith(
        status: WorkoutStatus.paused,
        statusChanges: <StatusChangeEvent>[
          ...session.statusChanges,
          pauseStatusChange,
        ],
      ),
      isTracking: false,
      elapsedTime: snapshot.activeDuration,
    );
  }

  /// Resume the paused workout
  Future<void> resumeWorkout() async {
    final session = state.currentSession;
    final timeline = _timeline;
    if (_isDisposed ||
        _isAccountExitQuiescing ||
        _isStarting ||
        _isStopping ||
        _isResetting ||
        session == null ||
        session.status != WorkoutStatus.paused ||
        timeline == null ||
        timeline.phase != WorkoutTimelinePhase.paused) {
      return;
    }

    try {
      final resumedTimeline = timeline.resume(_liveTrackingRepository.now());
      _timeline = resumedTimeline;
      _activeDistanceAnchor = null;
      _activeSegmentStartedAt = resumedTimeline.lastTransitionAt;
      final resumeStatusChange = StatusChangeEvent(
        status: WorkoutStatus.active,
        timestamp: resumedTimeline.lastTransitionAt,
      );
      final snapshot = resumedTimeline.snapshotAt(
        resumedTimeline.lastTransitionAt,
      );

      state = state.copyWith(
        currentSession: session.copyWith(
          status: WorkoutStatus.active,
          statusChanges: <StatusChangeEvent>[
            ...session.statusChanges,
            resumeStatusChange,
          ],
        ),
        isTracking: true,
        elapsedTime: snapshot.activeDuration,
        currentPace: 0,
      );
      _startElapsedTimer();
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Failed to resume workout. Please try again.',
      );
    }
  }

  /// Stop and complete the current workout
  Future<LiveWorkoutFinalizationResult> stopWorkout() {
    final pendingStop = _stopFuture;
    if (pendingStop != null) return pendingStop;

    late final Future<LiveWorkoutFinalizationResult> trackedStop;
    trackedStop = _stopWorkoutOnce().whenComplete(() {
      if (identical(_stopFuture, trackedStop)) {
        _stopFuture = null;
      }
    });
    _stopFuture = trackedStop;
    return trackedStop;
  }

  Future<LiveWorkoutFinalizationResult> _stopWorkoutOnce() async {
    final session = state.currentSession;
    final timeline = _timeline;
    if (_isDisposed ||
        _isStarting ||
        _isStopping ||
        _isResetting ||
        session == null ||
        (session.status != WorkoutStatus.active &&
            session.status != WorkoutStatus.paused) ||
        timeline == null) {
      return LiveWorkoutFinalizationResult(
        _unsavedCompletedWorkout == null
            ? LiveWorkoutFinalizationStatus.noActiveWorkout
            : LiveWorkoutFinalizationStatus.savePending,
      );
    }

    _isStopping = true;
    var result = const LiveWorkoutFinalizationResult(
      LiveWorkoutFinalizationStatus.failed,
    );
    try {
      final completedTimeline = timeline.complete(
        _liveTrackingRepository.now(),
      );
      _timeline = completedTimeline;
      final endTime =
          completedTimeline.completedAt ?? completedTimeline.lastTransitionAt;
      final timing = completedTimeline.snapshotAt(endTime);

      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      final subscription = _locationSubscription;
      final cleanupSucceeded = await _cleanupTrackingResources(subscription);

      // TODO: Get user weight from profile for calorie calculation
      const userWeight = 70.0; // Default weight, should come from user profile
      final completionMetrics = calculateWorkoutCompletionMetrics(
        distanceInMeters: session.totalDistance,
        activeDuration: timing.activeDuration,
        userWeightKilograms: userWeight,
      );

      final completedStatusChange = StatusChangeEvent(
        status: WorkoutStatus.completed,
        timestamp: endTime,
      );
      final updatedStatusChanges = <StatusChangeEvent>[
        ...session.statusChanges,
        completedStatusChange,
      ];
      final sessionWithFinalTimeline = session.copyWith(
        status: WorkoutStatus.completed,
        endTime: endTime,
        pausedDuration: timing.pausedDuration,
        statusChanges: updatedStatusChanges,
      );
      final elevationData = calculateSegmentedElevationData(
        WorkoutRouteSegmenter.buildActivePointSegments(
          sessionWithFinalTimeline,
        ),
      );

      final completedSession = sessionWithFinalTimeline.copyWith(
        averageSpeed: completionMetrics.averageSpeedMetersPerSecond,
        averagePace: completionMetrics.averagePaceMinutesPerKilometer,
        calories: completionMetrics.estimatedCalories,
        elevationGain: elevationData.gain,
        elevationLoss: elevationData.loss,
      );
      _unsavedCompletedWorkout = completedSession;

      if (!_isDisposed) {
        state = state.copyWith(
          currentSession: completedSession,
          isTracking: false,
          elapsedTime: timing.activeDuration,
          errorMessage:
              cleanupSucceeded
                  ? null
                  : 'Location tracking cleanup was incomplete.',
        );
      }

      _lastAcceptedPoint = null;
      _activeDistanceAnchor = null;
      _activeSegmentStartedAt = null;
      _timeline = null;

      final didSave = await _persistCompletedWorkout(completedSession);
      result = LiveWorkoutFinalizationResult(
        didSave
            ? LiveWorkoutFinalizationStatus.saved
            : LiveWorkoutFinalizationStatus.savePending,
      );
    } catch (_) {
      if (!_isDisposed) {
        state = state.copyWith(
          errorMessage: 'Failed to finish workout. Please try again.',
        );
      }
      result = const LiveWorkoutFinalizationResult(
        LiveWorkoutFinalizationStatus.failed,
      );
    } finally {
      _isStopping = false;
    }
    return result;
  }

  bool get hasUnsavedCompletedWorkout => _unsavedCompletedWorkout != null;

  bool get hasPendingTrackingCleanup => _cleanupRequired;

  Future<bool> retryUnsavedWorkoutSave() async {
    final workout = _unsavedCompletedWorkout;
    if (_isDisposed ||
        _isStarting ||
        _isStopping ||
        _isResetting ||
        workout == null) {
      return workout == null;
    }

    _isStopping = true;
    try {
      return await _persistCompletedWorkout(workout, clearSaveError: true);
    } finally {
      _isStopping = false;
    }
  }

  Future<void> discardWorkout({bool forAccountExit = false}) async {
    if (_isAccountExitQuiescing && !forAccountExit) return;
    final pendingStop = _stopFuture;
    if (pendingStop != null) {
      await pendingStop;
    }
    if (_isDisposed || _isStopping || _isResetting) return;
    _unsavedCompletedWorkout = null;
    await resetWorkout(forAccountExit: forAccountExit);
  }

  Future<bool> retryPendingTrackingCleanup() async {
    if (_isDisposed || _isStarting || _isStopping || _isResetting) {
      return false;
    }
    if (!_cleanupRequired) return true;

    _isResetting = true;
    try {
      final cleanupSucceeded = await _retryRequiredCleanup();
      if (!_isDisposed) {
        state = state.copyWith(
          errorMessage:
              cleanupSucceeded
                  ? null
                  : 'Location tracking cleanup is still pending.',
        );
      }
      return cleanupSucceeded;
    } finally {
      _isResetting = false;
    }
  }

  /// Cancels and awaits live operations already crossing an async boundary.
  Future<bool> quiesceForAccountExit() async {
    if (_isDisposed) return true;
    _isAccountExitQuiescing = true;

    final pendingStart = _startFuture;
    if (pendingStart != null) {
      _operationGeneration += 1;
      await pendingStart;
    }

    final pendingStop = _stopFuture;
    if (pendingStop != null) {
      await pendingStop;
    }

    return !_isStarting && !_isStopping && !_isResetting;
  }

  void resumeAfterBlockedAccountExit() {
    if (_isDisposed) return;
    _isAccountExitQuiescing = false;
  }

  Future<bool> _persistCompletedWorkout(
    WorkoutSessionEntity workout, {
    bool clearSaveError = false,
  }) async {
    try {
      await _workoutRepository.saveWorkout(workout);
      if (identical(_unsavedCompletedWorkout, workout)) {
        _unsavedCompletedWorkout = null;
      }
      if (!_isDisposed && clearSaveError) {
        state = state.copyWith(errorMessage: null);
      }
      try {
        await _onWorkoutAdded();
      } catch (_) {
        // A history refresh failure must not make the durable save look failed.
      }
      return true;
    } catch (_) {
      if (!_isDisposed) {
        state = state.copyWith(
          errorMessage: 'Workout is not saved yet. Keep this screen open.',
        );
      }
      return false;
    }
  }

  /// Handle new location updates
  void _onLocationUpdate(TrackingPointEntity point) {
    if (_isDisposed ||
        _isStarting ||
        _isStopping ||
        _isResetting ||
        state.currentSession == null) {
      return;
    }
    final session = state.currentSession!;
    if (session.status == WorkoutStatus.completed) return;

    final isWorkoutActive = session.status == WorkoutStatus.active;
    final decision = _pointAcceptancePolicy.evaluate(
      point: point,
      workoutType: session.type,
      isWorkoutActive: isWorkoutActive,
      previousAcceptedPoint: _lastAcceptedPoint,
      activeDistanceAnchor: _activeDistanceAnchor,
      activeSegmentStartedAt: _activeSegmentStartedAt,
    );
    if (!decision.accepted) return;

    _lastAcceptedPoint = point;
    if (!isWorkoutActive) {
      _activeDistanceAnchor = null;
      state = state.copyWith(currentLocation: point);
      return;
    }

    var currentPace = 0.0;
    if (decision.contributesActiveDistance && decision.timestampDelta != null) {
      currentPace =
          calculatePace(
            decision.distanceDeltaMeters,
            decision.timestampDelta!,
          ) ??
          0;
    }

    final impliedSpeed = decision.impliedSpeedMetersPerSecond ?? 0;
    final updatedSession = session.copyWith(
      trackingPoints: <TrackingPointEntity>[...session.trackingPoints, point],
      totalDistance: session.totalDistance + decision.distanceDeltaMeters,
      maxSpeed:
          impliedSpeed > session.maxSpeed ? impliedSpeed : session.maxSpeed,
    );
    if (decision.canAdvanceActiveDistanceAnchor) {
      _activeDistanceAnchor = point;
    }

    state = state.copyWith(
      currentSession: updatedSession,
      currentLocation: point,
      currentPace: currentPace,
    );
  }

  /// Handle location tracking errors
  void _onLocationError(Object error, StackTrace stackTrace) {
    if (_isDisposed) return;
    final session = state.currentSession;
    if (_isStarting ||
        _isStopping ||
        _isResetting ||
        session == null ||
        session.status == WorkoutStatus.completed) {
      return;
    }
    state = state.copyWith(errorMessage: 'Location tracking was interrupted.');
  }

  /// Start the elapsed time timer
  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = _periodicTimerFactory(const Duration(seconds: 1), (_) {
      if (_isDisposed || _isStarting || _isStopping || _isResetting) {
        return;
      }
      final timeline = _timeline;
      if (timeline == null ||
          timeline.phase != WorkoutTimelinePhase.active ||
          state.currentSession == null) {
        return;
      }

      final observedTimeline = timeline.observe(_liveTrackingRepository.now());
      _timeline = observedTimeline;
      final snapshot = observedTimeline.snapshotAt(
        observedTimeline.latestObservedAt,
      );
      state = state.copyWith(elapsedTime: snapshot.activeDuration);
    });
  }

  /// Clear error message
  void clearError() {
    if (_isDisposed) return;
    state = state.clearError();
  }

  bool _isOperationCurrent(int generation) {
    return !_isDisposed && generation == _operationGeneration;
  }

  Future<bool> _cleanupTrackingResources(
    StreamSubscription<TrackingPointEntity>? subscription,
  ) async {
    var subscriptionCancelled = true;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        subscriptionCancelled = false;
      }
    }

    if (subscriptionCancelled) {
      if (identical(_locationSubscription, subscription)) {
        _locationSubscription = null;
      }
    } else {
      _locationSubscription = subscription;
    }

    var sourceStopped = true;
    try {
      await _liveTrackingRepository.stopTracking();
    } catch (_) {
      sourceStopped = false;
    }

    _cleanupRequired = !subscriptionCancelled || !sourceStopped;
    return !_cleanupRequired;
  }

  Future<bool> _retryRequiredCleanup() {
    return _cleanupTrackingResources(_locationSubscription);
  }

  /// Reset workout state (useful for starting fresh)
  Future<void> resetWorkout({bool forAccountExit = false}) async {
    if (_isAccountExitQuiescing && !forAccountExit) return;
    if (_isDisposed || _isStopping || _isResetting) return;
    if (_unsavedCompletedWorkout != null) {
      state = state.copyWith(
        errorMessage:
            'The previous workout could not be saved. Reset is blocked.',
      );
      return;
    }

    _isResetting = true;
    _operationGeneration += 1;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    try {
      final cleanupSucceeded = await _cleanupTrackingResources(
        _locationSubscription,
      );
      _resetInternalTrackingState();

      if (!_isDisposed) {
        state = LiveTrackingState(
          errorMessage:
              cleanupSucceeded
                  ? null
                  : 'Location tracking cleanup is still pending.',
        );
      }
    } finally {
      _isResetting = false;
    }
  }

  void _resetInternalTrackingState() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _timeline = null;
    _lastAcceptedPoint = null;
    _activeDistanceAnchor = null;
    _activeSegmentStartedAt = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _operationGeneration += 1;
    final subscription = _locationSubscription;
    unawaited(_cleanupTrackingResources(subscription));
    _resetInternalTrackingState();
    super.dispose();
  }
}

// Provider definition
final StateNotifierProvider<LiveTrackingNotifier, LiveTrackingState>
liveTrackingProvider =
    StateNotifierProvider<LiveTrackingNotifier, LiveTrackingState>((ref) {
      final liveTrackingRepository = ref.watch(liveTrackingRepositoryProvider);
      final workoutRepository = ref.watch(workoutRepositoryProvider);
      return LiveTrackingNotifier(
        liveTrackingRepository,
        workoutRepository,
        currentUserId: () {
          final id = ref.read(sessionProvider).user?.id;
          return id == null ? null : int.tryParse(id);
        },
        onWorkoutAdded:
            () => ref.read(trackingHistoryProvider.notifier).onWorkoutAdded(),
      );
    });

// Convenience providers
final isTrackingProvider = Provider<bool>((ref) {
  return ref.watch(liveTrackingProvider.select((state) => state.isTracking));
});

final currentDistanceProvider = Provider<String>((ref) {
  return ref.watch(
    liveTrackingProvider.select((state) => state.formattedDistance),
  );
});

final currentPaceProvider = Provider<String>((ref) {
  return ref.watch(liveTrackingProvider.select((state) => state.formattedPace));
});

final elapsedTimeProvider = Provider<String>((ref) {
  return ref.watch(
    liveTrackingProvider.select((state) => state.formattedElapsedTime),
  );
});
