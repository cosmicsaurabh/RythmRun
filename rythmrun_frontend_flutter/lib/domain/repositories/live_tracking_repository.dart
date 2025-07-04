import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';

abstract class LiveTrackingRepository {
  Future<LocationServiceStatus> checkPermissions();

  Future<void> startTracking();

  Future<void> stopTracking();

  Future<TrackingPointEntity?> getCurrentLocation();

  double calculateDistance(
    TrackingPointEntity point1,
    TrackingPointEntity point2,
  );
  Future<double?> getCurrentElevation();
}
