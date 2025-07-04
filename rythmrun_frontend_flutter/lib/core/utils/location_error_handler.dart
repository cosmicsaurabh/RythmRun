import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';

/// Centralized location error handling utility
class LocationErrorHandler {
  /// Get user-friendly error message for location service status
  static String getLocationErrorMessage(LocationServiceStatus status) {
    switch (status) {
      case LocationServiceStatus.servicesDisabled:
        return 'Location services are disabled. Please enable them in device settings and restart the app.';
      case LocationServiceStatus.permissionDenied:
        return 'Location permission was denied. Please allow location access.';
      case LocationServiceStatus.permissionDeniedForever:
        return 'Location permission permanently denied. Please enable in app settings.';
      case LocationServiceStatus.granted:
        return 'Location permission granted';
    }
  }

  /// Check if location services are enabled
  static bool isLocationServicesEnabled(LocationServiceStatus status) {
    return status == LocationServiceStatus.granted;
  }

  /// Check if error is about location services being disabled
  static bool isLocationServicesDisabled(LocationServiceStatus status) {
    return status == LocationServiceStatus.servicesDisabled;
  }

  /// Check if error is about permission being denied
  static bool isPermissionDenied(LocationServiceStatus status) {
    return status == LocationServiceStatus.permissionDenied ||
        status == LocationServiceStatus.permissionDeniedForever;
  }

  /// Check if permission is permanently denied
  static bool isPermissionPermanentlyDenied(LocationServiceStatus status) {
    return status == LocationServiceStatus.permissionDeniedForever;
  }

  /// Get appropriate action text for the error
  static String getActionText(LocationServiceStatus status) {
    switch (status) {
      case LocationServiceStatus.servicesDisabled:
        return 'Open Settings';
      case LocationServiceStatus.permissionDenied:
        return 'Grant Permission';
      case LocationServiceStatus.permissionDeniedForever:
        return 'Open App Settings';
      case LocationServiceStatus.granted:
        return 'Continue';
    }
  }

  /// Get appropriate icon for the error
  static String getErrorIcon(LocationServiceStatus status) {
    switch (status) {
      case LocationServiceStatus.servicesDisabled:
        return 'location_disabled';
      case LocationServiceStatus.permissionDenied:
      case LocationServiceStatus.permissionDeniedForever:
        return 'location_off';
      case LocationServiceStatus.granted:
        return 'location_on';
    }
  }

  /// Get error title for UI display
  static String getErrorTitle(LocationServiceStatus status) {
    switch (status) {
      case LocationServiceStatus.servicesDisabled:
        return 'Location Services Disabled';
      case LocationServiceStatus.permissionDenied:
        return 'Location Permission Required';
      case LocationServiceStatus.permissionDeniedForever:
        return 'Location Permission Denied';
      case LocationServiceStatus.granted:
        return 'Location Access Granted';
    }
  }
}
