import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rythmrun_frontend_flutter/core/models/elevation_state_model.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';

enum LocationServiceStatus {
  granted,
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class TrackingService {
  static TrackingService? _instance;
  static TrackingService get instance => _instance ??= TrackingService._();

  TrackingService._();

  StreamSubscription<Position>? _positionSubscription;
  final StreamController<TrackingPointEntity> _locationController =
      StreamController<TrackingPointEntity>.broadcast();

  bool _isTracking = false;
  TrackingPointEntity? _lastPoint;

  /// Stream of location updates
  Stream<TrackingPointEntity> get locationStream => _locationController.stream;

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Check and request location permissions
  Future<LocationServiceStatus> checkPermissions() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationServiceStatus.servicesDisabled;
    }

    // Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationServiceStatus.permissionDenied;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationServiceStatus.permissionDeniedForever;
    }

    bool hasPermission =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    return hasPermission
        ? LocationServiceStatus.granted
        : LocationServiceStatus.permissionDenied;
  }

  /// Start tracking location updates
  Future<void> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.best,
    int distanceFilter = 5, // minimum distance in meters between updates
  }) async {
    if (_isTracking) return;

    // Check permissions first
    LocationServiceStatus permissionStatus = await checkPermissions();
    if (permissionStatus != LocationServiceStatus.granted) {
      throw Exception(
        LocationErrorHandler.getLocationErrorMessage(permissionStatus),
      );
    }

    // Configure location settings
    LocationSettings locationSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );

    try {
      // Start listening to position updates
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(_onLocationUpdate, onError: _onLocationError);

      _isTracking = true;
      log('🎯 Tracking started with accuracy: $accuracy');
    } catch (e) {
      throw Exception('Failed to start location tracking: $e');
    }
  }

  /// Stop tracking location updates
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _lastPoint = null;

    log('🛑 Tracking stopped');
  }

  /// Handle new location updates
  void _onLocationUpdate(Position position) {
    final point = TrackingPointEntity(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      timestamp: DateTime.now(),
    );

    // Optional: Filter out inaccurate readings
    if (position.accuracy > 50) {
      debugPrint(
        '⚠️ Skipping inaccurate reading: ${position.accuracy}m accuracy',
      );
      return;
    }

    _lastPoint = point;
    _locationController.add(point);

    debugPrint(
      '📍 Location update: ${point.latitude}, ${point.longitude}, ${point.accuracy}m accuracy ${point.speed}m/s speed ${point.heading}° heading ${point.altitude}m altitude ${point.timestamp} timestamp',
    );
  }

  /// Handle location errors
  void _onLocationError(dynamic error) {
    debugPrint('❌ Location error: $error');
    _locationController.addError(error);
  }

  /// Calculate distance between two points using Haversine formula
  static double calculateDistance(
    TrackingPointEntity point1,
    TrackingPointEntity point2,
  ) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Calculate pace in minutes per kilometer
  static double? calculatePace(double distanceInMeters, Duration duration) {
    if (distanceInMeters <= 0 || duration.inSeconds <= 0) return null;

    double distanceInKm = distanceInMeters / 1000;
    double timeInMinutes = duration.inSeconds / 60;

    return timeInMinutes / distanceInKm; // minutes per km
  }

  /// Calculate speed in km/h
  static double calculateSpeed(double distanceInMeters, Duration duration) {
    if (duration.inSeconds <= 0 || distanceInMeters <= 0) return 0.0;

    double distanceInKm = distanceInMeters / 1000;
    double timeInHours = duration.inSeconds / 3600;

    return distanceInKm / timeInHours; // km/h
  }

  /// Estimate calories burned (simple calculation based on MET values)
  static int estimateCalories({
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

  /// Get current location (one-time)
  Future<TrackingPointEntity?> getCurrentLocation() async {
    try {
      LocationServiceStatus permissionStatus = await checkPermissions();
      if (permissionStatus != LocationServiceStatus.granted) return null;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return TrackingPointEntity(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('❌ Failed to get current location: $e');
      return null;
    }
  }

  void dispose() {
    stopTracking();
    _locationController.close();
  }

  /// Calculate elevation gain and loss from tracking points
  static ElevationState calculateElevationData(
    List<TrackingPointEntity> points,
  ) {
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
    final smoothedPoints = _smoothElevationData(pointsWithAltitude);

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
  static List<TrackingPointEntity> _smoothElevationData(
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

  /// Get current elevation using GPS
  Future<double?> getCurrentElevation() async {
    try {
      final location = await getCurrentLocation();
      return location?.altitude;
    } catch (e) {
      debugPrint('❌ Failed to get current elevation: $e');
      return null;
    }
  }
}
