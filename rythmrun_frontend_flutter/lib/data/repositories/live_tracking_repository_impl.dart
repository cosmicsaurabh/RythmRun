import 'dart:async';

import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';

class LiveTrackingRepositoryImpl implements LiveTrackingRepository {
  final LiveTrackingService _service;
  final DateTime Function() _now;

  LiveTrackingRepositoryImpl({
    LiveTrackingService? service,
    DateTime Function()? now,
  }) : _service = service ?? LiveTrackingService.instance,
       _now = now ?? DateTime.now;

  @override
  Stream<TrackingPointEntity> get locationStream => _service.locationStream;

  @override
  DateTime now() => _now();

  @override
  Future<LocationServiceStatus> checkPermissions() async {
    return await _service.checkPermissions();
  }

  @override
  Future<void> startTracking() async {
    await _service.startTracking();
  }

  @override
  Future<void> stopTracking() async {
    await _service.stopTracking();
  }

  @override
  Future<TrackingPointEntity?> getCurrentLocation() async {
    return await _service.getCurrentLocation();
  }

  @override
  Future<double?> getCurrentElevation() async {
    return await _service.getCurrentElevation();
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
    return await _service.requestLocationService();
  }
}
