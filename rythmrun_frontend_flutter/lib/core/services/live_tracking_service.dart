import 'dart:async';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as location_plugin;
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
  }

  /// Handle new location updates
  void _onLocationUpdate(Position position) {
    final point = mapPosition(position);

    // Validation belongs to the versioned acceptance policy in the notifier.
    _locationController.add(point);
  }

  /// Handle location errors
  void _onLocationError(dynamic error) {
    _locationController.addError(error);
  }

  /// Get current location (one-time)
  Future<TrackingPointEntity?> getCurrentLocation() async {
    try {
      LocationServiceStatus permissionStatus = await checkPermissions();
      if (permissionStatus != LocationServiceStatus.granted) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10), // Add timeout
        ),
      );

      // Validate the position
      if (position.latitude == 0.0 && position.longitude == 0.0) {
        return null;
      }

      return mapPosition(position);
    } catch (_) {
      return null;
    }
  }

  /// Convert the platform sample without replacing its acquisition timestamp.
  static TrackingPointEntity mapPosition(Position position) {
    return TrackingPointEntity(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
    );
  }

  Future<void> dispose() async {
    await stopTracking();
    await _locationController.close();
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
    } catch (_) {
      return null;
    }
  }

  /// Request location service to be enabled (shows system dialog on Android)
  /// Returns true if location service was enabled, false otherwise
  /// On iOS, this will open location settings
  Future<bool> requestLocationService() async {
    try {
      // Only use location plugin's requestService on Android
      // On iOS, fall back to opening settings
      if (Platform.isAndroid) {
        final location = location_plugin.Location();
        bool serviceEnabled = await location.serviceEnabled();

        if (!serviceEnabled) {
          // This shows the Samsung-style system dialog with "Turn on" button
          serviceEnabled = await location.requestService();
          if (serviceEnabled) {
            return true;
          } else {
            return false;
          }
        } else {
          // Already enabled
          return true;
        }
      } else {
        // iOS: open location settings
        await Geolocator.openLocationSettings();
        return false; // We can't know if user enabled it, so return false
      }
    } catch (_) {
      // Fallback: open location settings
      try {
        await Geolocator.openLocationSettings();
      } catch (_) {
        // Ignore errors opening settings
      }
      return false;
    }
  }
}
