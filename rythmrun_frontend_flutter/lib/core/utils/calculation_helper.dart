import 'package:rythmrun_frontend_flutter/core/models/elevation_state_model.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';

/// Calculate pace in minutes per kilometer
double? calculatePace(double distanceInMeters, Duration duration) {
  if (distanceInMeters <= 0 || duration.inSeconds <= 0) return null;

  double distanceInKm = distanceInMeters / 1000;
  double timeInMinutes = duration.inSeconds / 60;

  return timeInMinutes / distanceInKm; // minutes per km
}

/// Calculate speed in km/h
double calculateSpeed(double distanceInMeters, Duration duration) {
  if (duration.inSeconds <= 0 || distanceInMeters <= 0) return 0.0;

  double distanceInKm = distanceInMeters / 1000;
  double timeInHours = duration.inSeconds / 3600;

  return distanceInKm / timeInHours; // km/h
}

/// Estimate calories burned (simple calculation based on MET values)
int estimateCalories({
  required double distanceInKm,
  required Duration duration,
  required double userWeightKg,
  double averageSpeedKmh = 8.0, // default running speed
}) {
  if (duration.inSeconds <= 0 || distanceInKm <= 0 || userWeightKg <= 0)
    return 0;

  // MET values for different activities
  double met;
  if (averageSpeedKmh < 6) {
    met = 6.0; // walking
  } else if (averageSpeedKmh < 10) {
    met = 9.8; // jogging
  } else if (averageSpeedKmh < 13) {
    met = 11.0; // running
  } else {
    met = 14.5; // fast running
  }

  double timeInHours = duration.inSeconds / 3600;
  return (met * userWeightKg * timeInHours).round();
}

/// Calculate elevation gain and loss from tracking points
ElevationState calculateElevationData(List<TrackingPointEntity> points) {
  if (points.length < 2) {
    return ElevationState(gain: 0.0, loss: 0.0);
  }

  double totalGain = 0.0;
  double totalLoss = 0.0;

  // Filter out points without altitude data
  final pointsWithAltitude =
      points.where((point) => point.altitude != null).toList();

  if (pointsWithAltitude.length < 2) {
    return ElevationState(gain: 0.0, loss: 0.0);
  }

  // Apply smoothing to reduce GPS noise
  final smoothedPoints = smoothElevationData(pointsWithAltitude);

  for (int i = 1; i < smoothedPoints.length; i++) {
    final previousAltitude = smoothedPoints[i - 1].altitude!;
    final currentAltitude = smoothedPoints[i].altitude!;
    final difference = currentAltitude - previousAltitude;

    // Only count significant elevation changes (reduce noise)
    if (difference.abs() > 2.0) {
      // minimum 2m change
      if (difference > 0) {
        totalGain += difference;
      } else {
        totalLoss += difference.abs();
      }
    }
  }

  return ElevationState(gain: totalGain, loss: totalLoss);
}

/// Apply simple moving average to smooth elevation data
List<TrackingPointEntity> smoothElevationData(
  List<TrackingPointEntity> points,
) {
  if (points.length < 3) return points;

  final smoothedPoints = <TrackingPointEntity>[];

  // Keep first point as-is
  smoothedPoints.add(points.first);

  // Apply 3-point moving average for middle points
  for (int i = 1; i < points.length - 1; i++) {
    final prev = points[i - 1].altitude!;
    final current = points[i].altitude!;
    final next = points[i + 1].altitude!;

    final smoothedAltitude = (prev + current + next) / 3;

    smoothedPoints.add(points[i].copyWith(altitude: smoothedAltitude));
  }

  // Keep last point as-is
  smoothedPoints.add(points.last);

  return smoothedPoints;
}
