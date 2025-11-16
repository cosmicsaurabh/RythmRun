import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';

class LiveTrackingRepositoryImpl implements LiveTrackingRepository {
  @override
  Future<LocationServiceStatus> checkPermissions() async {
    return await LiveTrackingService.instance.checkPermissions();
  }

  @override
  Future<void> startTracking() async {
    await LiveTrackingService.instance.startTracking();
  }

  @override
  Future<void> stopTracking() async {
    await LiveTrackingService.instance.stopTracking();
  }

  @override
  Future<TrackingPointEntity?> getCurrentLocation() async {
    return await LiveTrackingService.instance.getCurrentLocation();
  }

  @override
  Future<double?> getCurrentElevation() async {
    return await LiveTrackingService.instance.getCurrentElevation();
  }

  @override
  double calculateDistance(
    TrackingPointEntity point1,
    TrackingPointEntity point2,
  ) {
    return LiveTrackingService.calculateDistance(point1, point2);
  }

  @override
  Future<bool> requestLocationService() async {
    return await LiveTrackingService.instance.requestLocationService();
  }
}
