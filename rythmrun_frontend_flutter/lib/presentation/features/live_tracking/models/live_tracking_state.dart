import 'package:flutter/foundation.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

@immutable
class LiveTrackingState {
  final WorkoutSessionEntity? currentSession;
  final bool isTracking;
  final bool isLoading;
  final String? errorMessage;
  final TrackingPointEntity? currentLocation;
  final Duration elapsedTime;
  final double currentPace; // current pace in min/km
  final bool hasLocationPermission;
  final LocationServiceStatus? locationServiceStatus;

  const LiveTrackingState({
    this.currentSession,
    this.isTracking = false,
    this.isLoading = false,
    this.errorMessage,
    this.currentLocation,
    this.elapsedTime = Duration.zero,
    this.currentPace = 0.0,
    this.hasLocationPermission = false,
    this.locationServiceStatus,
  });

  LiveTrackingState copyWith({
    WorkoutSessionEntity? currentSession,
    bool? isTracking,
    bool? isLoading,
    String? errorMessage,
    bool? clearErrorMessage,
    TrackingPointEntity? currentLocation,
    Duration? elapsedTime,
    double? currentPace,
    bool? hasLocationPermission,
    LocationServiceStatus? locationServiceStatus,
  }) {
    return LiveTrackingState(
      currentSession: currentSession ?? this.currentSession,
      isTracking: isTracking ?? this.isTracking,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage == true ? null : errorMessage ?? this.errorMessage,
      currentLocation: currentLocation ?? this.currentLocation,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      currentPace: currentPace ?? this.currentPace,
      hasLocationPermission:
          hasLocationPermission ?? this.hasLocationPermission,
      locationServiceStatus:
          locationServiceStatus ?? this.locationServiceStatus,
    );
  }

  /// Clear error message
  LiveTrackingState clearError() {
    return copyWith(clearErrorMessage: true);
  }

  ////----------------------Checkers----------------------

  /// Check if there's an active workout session
  bool get hasActiveSession =>
      currentSession != null && !currentSession!.isCompleted;

  /// Check if workout is paused
  bool get isPaused => currentSession?.isPaused ?? false;

  /// Get current distance in a readable format
  String get formattedDistance {
    if (currentSession == null) return '0.00 km';
    double km = currentSession!.totalDistance / 1000;
    return '${km.toStringAsFixed(2)} km';
  }

  ////----------------------Formatted valueus----------------------

  /// Get current pace in a readable format
  String get formattedPace {
    if (currentPace <= 0) return '--:--';
    int minutes = currentPace.floor();
    int seconds = ((currentPace - minutes) * 60).round();
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get elapsed time in a readable format
  String get formattedElapsedTime {
    int hours = elapsedTime.inHours;
    int minutes = elapsedTime.inMinutes.remainder(60);
    int seconds = elapsedTime.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(1, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Get average speed in km/h
  String get formattedAverageSpeed {
    if (currentSession == null || currentSession!.averageSpeed <= 0) {
      return '0.0 km/h';
    }
    double kmh = currentSession!.averageSpeed * 3.6; // m/s to km/h
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  ////--------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveTrackingState &&
          runtimeType == other.runtimeType &&
          currentSession == other.currentSession &&
          isTracking == other.isTracking &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage &&
          elapsedTime == other.elapsedTime;

  @override
  int get hashCode =>
      currentSession.hashCode ^
      isTracking.hashCode ^
      isLoading.hashCode ^
      errorMessage.hashCode ^
      elapsedTime.hashCode;

  @override
  String toString() {
    return 'LiveTrackingState{isTracking: $isTracking, hasSession: ${currentSession != null}, distance: $formattedDistance, locationServiceStatus: $locationServiceStatus, hasLocationPermission: $hasLocationPermission, errorMessage: $errorMessage }';
  }
}
