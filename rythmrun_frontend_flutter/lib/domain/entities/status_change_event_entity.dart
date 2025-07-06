import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';

class StatusChangeEvent {
  final WorkoutStatus status;
  final DateTime timestamp;

  const StatusChangeEvent({required this.status, required this.timestamp});

  StatusChangeEvent copyWith({WorkoutStatus? status, DateTime? timestamp}) {
    return StatusChangeEvent(
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {'status': status.name, 'timestamp': timestamp.toIso8601String()};
  }

  factory StatusChangeEvent.fromMap(Map<String, dynamic> map) {
    return StatusChangeEvent(
      status: WorkoutStatus.values.firstWhere((e) => e.name == map['status']),
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  @override
  String toString() {
    return 'StatusChangeEvent(status: $status, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StatusChangeEvent &&
        other.status == status &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => status.hashCode ^ timestamp.hashCode;
}
