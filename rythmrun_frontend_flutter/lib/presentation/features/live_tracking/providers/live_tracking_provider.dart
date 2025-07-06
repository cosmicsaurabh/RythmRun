import 'dart:async';
import 'dart:developer';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/calculation_helper.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';

class LiveTrackingNotifier extends StateNotifier<LiveTrackingState> {
  final LiveTrackingRepository _liveTrackingRepository;
  final WorkoutRepository _workoutRepository;
  final Ref _ref;

  StreamSubscription<TrackingPointEntity>? _locationSubscription;
  Timer? _elapsedTimer;
  DateTime? _sessionStartTime;
  DateTime? _pausedTime;
  Duration _totalPausedDuration = Duration.zero;

  LiveTrackingNotifier(
    this._liveTrackingRepository,
    this._workoutRepository,
    this._ref,
  ) : super(const LiveTrackingState());

  /// Check location permissions
  Future<void> checkPermissions() async {
    try {
      state = state.copyWith(isLoading: true);
      LocationServiceStatus permissionStatus =
          await _liveTrackingRepository.checkPermissions();

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
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to check location permissions: $e',
        hasLocationPermission: false,
        locationServiceStatus: LocationServiceStatus.permissionDenied,
      );
    }
  }

  /// Start a new workout session
  Future<void> startWorkout(WorkoutType type) async {
    try {
      // Clear any previous error
      state = state.copyWith(isLoading: true, errorMessage: null);

      // Check permissions first
      if (!state.hasLocationPermission) {
        await checkPermissions();
        if (!state.hasLocationPermission) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'Location permission is required to track workouts',
          );
          return;
        }
      }

      // Get current user ID
      final sessionData = _ref.read(sessionProvider);
      final userId = sessionData.user?.id;
      if (userId == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'User not authenticated',
        );
        return;
      }

      // Create initial status change event
      final startTime = DateTime.now();
      final initialStatusChange = StatusChangeEvent(
        status: WorkoutStatus.active,
        timestamp: startTime,
      );

      // Create new workout session
      final newSession = WorkoutSessionEntity(
        type: type,
        status: WorkoutStatus.active,
        startTime: startTime,
        statusChanges: [initialStatusChange],
        userId: int.parse(userId.toString()),
      );

      // Start location tracking
      await _liveTrackingRepository.startTracking();

      // Set up location updates listener
      _locationSubscription = LiveTrackingService.instance.locationStream
          .listen(_onLocationUpdate, onError: _onLocationError);

      // Start elapsed time timer
      _startElapsedTimer();

      state = state.copyWith(
        currentSession: newSession,
        isTracking: true,
        isLoading: false,
        elapsedTime: Duration.zero,
      );

      _sessionStartTime = DateTime.now();
      log('🏃 Workout started: ${type.name}');
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to start workout: $e',
      );
    }
  }

  /// Pause the current workout
  void pauseWorkout() {
    if (state.currentSession == null || !state.isTracking) return;

    // Don't stop GPS tracking during pause - keep collecting points
    // _liveTrackingRepository.stopTracking();
    // _locationSubscription?.cancel();
    _elapsedTimer?.cancel();

    _pausedTime = DateTime.now();

    // Create pause status change event
    final pauseStatusChange = StatusChangeEvent(
      status: WorkoutStatus.paused,
      timestamp: _pausedTime!,
    );

    // Add status change to session
    final updatedStatusChanges = [
      ...state.currentSession!.statusChanges,
      pauseStatusChange,
    ];

    state = state.copyWith(
      currentSession: state.currentSession!.copyWith(
        status: WorkoutStatus.paused,
        statusChanges: updatedStatusChanges,
      ),
      isTracking: false,
    );

    log('⏸️ Workout paused at ${_pausedTime}');
  }

  /// Resume the paused workout
  Future<void> resumeWorkout() async {
    if (state.currentSession == null ||
        state.currentSession!.status != WorkoutStatus.paused)
      return;

    try {
      final resumeTime = DateTime.now();

      // Calculate paused duration
      if (_pausedTime != null) {
        _totalPausedDuration += resumeTime.difference(_pausedTime!);
      }

      // Create resume status change event
      final resumeStatusChange = StatusChangeEvent(
        status: WorkoutStatus.active,
        timestamp: resumeTime,
      );

      // Add status change to session
      final updatedStatusChanges = [
        ...state.currentSession!.statusChanges,
        resumeStatusChange,
      ];

      // Location tracking should already be running (not stopped during pause)
      // await _liveTrackingRepository.startTracking();
      // _locationSubscription = LiveTrackingService.instance.locationStream
      //     .listen(_onLocationUpdate, onError: _onLocationError);

      // Resume elapsed timer
      _startElapsedTimer();

      state = state.copyWith(
        currentSession: state.currentSession!.copyWith(
          status: WorkoutStatus.active,
          statusChanges: updatedStatusChanges,
        ),
        isTracking: true,
      );

      log('▶️ Workout resumed at $resumeTime');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to resume workout: $e');
    }
  }

  /// Stop and complete the current workout
  Future<void> stopWorkout() async {
    if (state.currentSession == null) return;

    // Stop tracking and timers
    await _liveTrackingRepository.stopTracking();
    _locationSubscription?.cancel();
    _elapsedTimer?.cancel();

    // Calculate final metrics
    final session = state.currentSession!;
    final endTime = DateTime.now();
    final totalDuration = endTime.difference(session.startTime!);
    final activeDuration = totalDuration - _totalPausedDuration;

    // Calculate final statistics
    double averageSpeed = 0;
    double? averagePace;
    if (session.totalDistance > 0 && activeDuration.inSeconds > 0) {
      averageSpeed = calculateSpeed(session.totalDistance, activeDuration);
      averagePace = calculatePace(session.totalDistance, activeDuration);
    }

    // Calculate elevation gain and loss
    final elevationData = calculateElevationData(session.trackingPoints);

    // TODO: Get user weight from profile for calorie calculation
    const userWeight = 70.0; // Default weight, should come from user profile
    final calories = estimateCalories(
      distanceInKm: session.totalDistance / 1000,
      duration: activeDuration,
      userWeightKg: userWeight,
      averageSpeedKmh: averageSpeed * 3.6,
    );

    // Add final completed status change event
    final completedStatusChange = StatusChangeEvent(
      status: WorkoutStatus.completed,
      timestamp: endTime,
    );

    final updatedStatusChanges = [
      ...session.statusChanges,
      completedStatusChange,
    ];

    final completedSession = session.copyWith(
      status: WorkoutStatus.completed,
      endTime: endTime,
      pausedDuration: _totalPausedDuration,
      averageSpeed: averageSpeed,
      averagePace: averagePace,
      calories: calories,
      elevationGain: elevationData.gain,
      elevationLoss: elevationData.loss,
      statusChanges: updatedStatusChanges,
    );

    state = state.copyWith(currentSession: completedSession, isTracking: false);

    // Reset tracking state
    _sessionStartTime = null;
    _pausedTime = null;
    _totalPausedDuration = Duration.zero;

    log(
      '🏁 Workout completed: ${session.totalDistance}m in ${activeDuration.inMinutes} minutes',
    );
    log('📊 Status changes count: ${completedSession.statusChanges.length}');
    for (int i = 0; i < completedSession.statusChanges.length; i++) {
      final change = completedSession.statusChanges[i];
      log('  $i: ${change.status.name} at ${change.timestamp}');
    }

    // Save to database
    try {
      final workoutId = await _workoutRepository.saveWorkout(completedSession);
      log(
        '💾 Workout saved with ID: $workoutId (including ${completedSession.statusChanges.length} status changes)',
      );

      // Workout saved successfully

      // Test retrieval to verify data integrity
      _testWorkoutRetrieval(workoutId);
    } catch (e) {
      log('❌ Failed to save workout: $e');
      state = state.copyWith(errorMessage: 'Failed to save workout: $e');
    }
  }

  /// Test workout retrieval to verify data integrity
  Future<void> _testWorkoutRetrieval(int workoutId) async {
    try {
      final retrievedWorkout = await _workoutRepository.getWorkout(workoutId);
      if (retrievedWorkout != null) {
        log('✅ Workout retrieval test successful');
        log(
          '📊 Retrieved ${retrievedWorkout.trackingPoints.length} tracking points',
        );
        log(
          '📊 Retrieved ${retrievedWorkout.statusChanges.length} status changes',
        );

        for (int i = 0; i < retrievedWorkout.statusChanges.length; i++) {
          final change = retrievedWorkout.statusChanges[i];
          log('   Retrieved: ${change.status.name} at ${change.timestamp}');
        }
      } else {
        log('❌ Workout retrieval test failed: workout not found');
      }
    } catch (e) {
      log('❌ Workout retrieval test failed: $e');
    }
  }

  /// Handle new location updates
  void _onLocationUpdate(TrackingPointEntity point) {
    if (state.currentSession == null) return;
    final session = state.currentSession!;
    final newPoints = [...session.trackingPoints, point];

    // Calculate new distance
    double newDistance = session.totalDistance;
    if (session.trackingPoints.isNotEmpty) {
      final lastPoint = session.trackingPoints.last;
      newDistance += LiveTrackingService.calculateDistance(lastPoint, point);
    }

    // Calculate current pace (based on last few points for more responsive updates)
    double currentPace = 0;
    if (newPoints.length >= 2) {
      final recentPoints =
          newPoints.length > 5
              ? newPoints.sublist(newPoints.length - 5)
              : newPoints;
      if (recentPoints.length >= 2) {
        double recentDistance = 0;
        for (int i = 1; i < recentPoints.length; i++) {
          recentDistance += LiveTrackingService.calculateDistance(
            recentPoints[i - 1],
            recentPoints[i],
          );
        }
        final recentDuration = recentPoints.last.timestamp.difference(
          recentPoints.first.timestamp,
        );
        final pace = calculatePace(recentDistance, recentDuration);
        if (pace != null && pace > 0 && pace < 30) {
          // reasonable pace range
          currentPace = pace;
        }
      }
    }

    // Calculate max speed
    double maxSpeed = session.maxSpeed;
    if (point.speed != null && point.speed! > maxSpeed) {
      maxSpeed = point.speed!;
    }

    final updatedSession = session.copyWith(
      trackingPoints: newPoints,
      totalDistance: newDistance,
      maxSpeed: maxSpeed,
    );

    state = state.copyWith(
      currentSession: updatedSession,
      currentLocation: point,
      currentPace: currentPace,
    );
  }

  /// Handle location tracking errors
  void _onLocationError(dynamic error) {
    log('❌ Location tracking error: $error');
    state = state.copyWith(errorMessage: 'Location tracking error: $error');
  }

  /// Start the elapsed time timer
  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.currentSession != null && _sessionStartTime != null) {
        final elapsed =
            DateTime.now().difference(_sessionStartTime!) -
            _totalPausedDuration;
        state = state.copyWith(elapsedTime: elapsed);
      }
    });
  }

  /// Clear error message
  void clearError() {
    state = state.clearError();
  }

  /// Reset workout state (useful for starting fresh)
  void resetWorkout() {
    _liveTrackingRepository.stopTracking();
    _locationSubscription?.cancel();
    _elapsedTimer?.cancel();

    _sessionStartTime = null;
    _pausedTime = null;
    _totalPausedDuration = Duration.zero;

    state = const LiveTrackingState();
  }

  @override
  void dispose() {
    _liveTrackingRepository.stopTracking();
    _locationSubscription?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }
}

// Provider definition
final liveTrackingProvider =
    StateNotifierProvider<LiveTrackingNotifier, LiveTrackingState>((ref) {
      final workoutRepository = ref.watch(workoutRepositoryProvider);
      final liveTrackingRepository = ref.watch(liveTrackingRepositoryProvider);
      return LiveTrackingNotifier(
        liveTrackingRepository,
        workoutRepository,
        ref,
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
