class TrackingPointEntity {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime timestamp;

  const TrackingPointEntity({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.heading,
    required this.timestamp,
  });

  /// Create a copy of this entity with updated values
  TrackingPointEntity copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? accuracy,
    double? speed,
    double? heading,
    DateTime? timestamp,
  }) {
    return TrackingPointEntity(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackingPointEntity &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      latitude.hashCode ^ longitude.hashCode ^ timestamp.hashCode;

  @override
  String toString() {
    return 'TrackingPointEntity{lat: $latitude, lng: $longitude, time: $timestamp}';
  }
}
