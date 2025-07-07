import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

double calculateDistance(LatLng point1, LatLng point2) {
  const double earthRadius = 6371000; // Earth's radius in meters

  double lat1Rad = point1.latitude * (pi / 180);
  double lat2Rad = point2.latitude * (pi / 180);
  double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
  double deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);

  double a =
      sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
      cos(lat1Rad) * cos(lat2Rad) * sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
  double c = 2 * asin(sqrt(a));

  return earthRadius * c;
}

// Get marker color based on workout type and speed
Color getCurrentLocationMarkerColor(
  TrackingPointEntity point,
  WorkoutSessionEntity? session,
) {
  // If there's an active workout, use workout color
  if (session != null) {
    return getWorkoutColor(session.type);
  }

  // Otherwise, use speed-based color
  final speed = point.speed ?? 0.0; // m/s
  if (speed < 0.5) return Colors.grey; // Stationary
  if (speed < 1.5) return Colors.blue; // Walking
  if (speed < 3.0) return Colors.orange; // Jogging
  return Colors.red; // Running
}

// Get marker icon based on workout type
IconData getCurrentLocationIcon(WorkoutSessionEntity? session) {
  if (session != null) {
    switch (session.type) {
      case WorkoutType.running:
        return runningIcon;
      case WorkoutType.walking:
        return walkingIcon;
      case WorkoutType.cycling:
        return cyclingIcon;
      case WorkoutType.hiking:
        return hikingIcon;
    }
  }

  return Icons.my_location; // Default
}

String getWorkoutTypeName(WorkoutType type) {
  switch (type) {
    case WorkoutType.running:
      return 'Running';
    case WorkoutType.walking:
      return 'Walking';
    case WorkoutType.cycling:
      return 'Cycling';
    case WorkoutType.hiking:
      return 'Hiking';
  }
}

WorkoutType getReverseWorkoutTypeName(String type) {
  switch (type.toLowerCase()) {
    case 'running':
      return WorkoutType.running;
    case 'walking':
      return WorkoutType.walking;
    case 'cycling':
      return WorkoutType.cycling;
    case 'hiking':
      return WorkoutType.hiking;
    default:
      throw ArgumentError('Unknown workout type: $type');
  }
}

IconData getWorkoutIcon(WorkoutType type) {
  switch (type) {
    case WorkoutType.running:
      return runningIcon;
    case WorkoutType.walking:
      return walkingIcon;
    case WorkoutType.cycling:
      return cyclingIcon;
    case WorkoutType.hiking:
      return hikingIcon;
  }
}

Color getWorkoutColor(WorkoutType type) {
  switch (type) {
    case WorkoutType.running:
      return CustomAppColors.running;
    case WorkoutType.walking:
      return CustomAppColors.walking;
    case WorkoutType.cycling:
      return CustomAppColors.cycling;
    case WorkoutType.hiking:
      return CustomAppColors.hiking;
  }
}
