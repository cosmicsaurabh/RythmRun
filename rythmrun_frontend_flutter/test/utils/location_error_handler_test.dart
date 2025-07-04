import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';

void main() {
  group('LocationErrorHandler', () {
    test('should return correct error messages for all statuses', () {
      // Test services disabled
      expect(
        LocationErrorHandler.getLocationErrorMessage(
          LocationServiceStatus.servicesDisabled,
        ),
        'Location services are disabled. Please enable them in device settings and restart the app.',
      );

      // Test permission denied
      expect(
        LocationErrorHandler.getLocationErrorMessage(
          LocationServiceStatus.permissionDenied,
        ),
        'Location permission was denied. Please allow location access.',
      );

      // Test permission denied forever
      expect(
        LocationErrorHandler.getLocationErrorMessage(
          LocationServiceStatus.permissionDeniedForever,
        ),
        'Location permission permanently denied. Please enable in app settings.',
      );

      // Test granted
      expect(
        LocationErrorHandler.getLocationErrorMessage(
          LocationServiceStatus.granted,
        ),
        'Location permission granted',
      );
    });

    test('should return correct action text for all statuses', () {
      expect(
        LocationErrorHandler.getActionText(
          LocationServiceStatus.servicesDisabled,
        ),
        'Open Settings',
      );

      expect(
        LocationErrorHandler.getActionText(
          LocationServiceStatus.permissionDenied,
        ),
        'Grant Permission',
      );

      expect(
        LocationErrorHandler.getActionText(
          LocationServiceStatus.permissionDeniedForever,
        ),
        'Open App Settings',
      );

      expect(
        LocationErrorHandler.getActionText(LocationServiceStatus.granted),
        'Continue',
      );
    });

    test('should return correct error titles for all statuses', () {
      expect(
        LocationErrorHandler.getErrorTitle(
          LocationServiceStatus.servicesDisabled,
        ),
        'Location Services Disabled',
      );

      expect(
        LocationErrorHandler.getErrorTitle(
          LocationServiceStatus.permissionDenied,
        ),
        'Location Permission Required',
      );

      expect(
        LocationErrorHandler.getErrorTitle(
          LocationServiceStatus.permissionDeniedForever,
        ),
        'Location Permission Denied',
      );

      expect(
        LocationErrorHandler.getErrorTitle(LocationServiceStatus.granted),
        'Location Access Granted',
      );
    });

    test('should correctly identify permission states', () {
      expect(
        LocationErrorHandler.isLocationServicesDisabled(
          LocationServiceStatus.servicesDisabled,
        ),
        true,
      );

      expect(
        LocationErrorHandler.isLocationServicesDisabled(
          LocationServiceStatus.permissionDenied,
        ),
        false,
      );

      expect(
        LocationErrorHandler.isPermissionDenied(
          LocationServiceStatus.permissionDenied,
        ),
        true,
      );

      expect(
        LocationErrorHandler.isPermissionDenied(
          LocationServiceStatus.permissionDeniedForever,
        ),
        true,
      );

      expect(
        LocationErrorHandler.isPermissionDenied(LocationServiceStatus.granted),
        false,
      );

      expect(
        LocationErrorHandler.isPermissionPermanentlyDenied(
          LocationServiceStatus.permissionDeniedForever,
        ),
        true,
      );

      expect(
        LocationErrorHandler.isPermissionPermanentlyDenied(
          LocationServiceStatus.permissionDenied,
        ),
        false,
      );
    });
  });
}
