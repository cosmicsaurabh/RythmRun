import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';

void main() {
  test('maps the native GPS timestamp and values without replacement', () {
    final acquiredAt = DateTime.utc(2026, 7, 11, 10, 30, 45);
    final position = Position(
      longitude: 77.123,
      latitude: 12.456,
      timestamp: acquiredAt,
      accuracy: 7,
      altitude: 100,
      altitudeAccuracy: 3,
      heading: 90,
      headingAccuracy: 4,
      speed: 2.5,
      speedAccuracy: 0.5,
    );

    final point = LiveTrackingService.mapPosition(position);

    expect(point.latitude, position.latitude);
    expect(point.longitude, position.longitude);
    expect(point.altitude, position.altitude);
    expect(point.accuracy, position.accuracy);
    expect(point.heading, position.heading);
    expect(point.speed, position.speed);
    expect(point.timestamp, same(acquiredAt));
  });
}
