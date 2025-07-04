import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';

enum LocationServiceStatus {
  granted,
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LiveTrackingService {
  static LiveTrackingService? _instance;
  static LiveTrackingService get instance =>
      _instance ??= LiveTrackingService._();

  LiveTrackingService._();

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
