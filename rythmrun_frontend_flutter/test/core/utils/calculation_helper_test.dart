import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/utils/calculation_helper.dart';

void main() {
  group('canonical workout calculations', () {
    test('calculates average speed in metres per second', () {
      expect(
        calculateAverageSpeedMetersPerSecond(10000, const Duration(hours: 1)),
        closeTo(2.7777777778, 0.0000000001),
      );
      expect(
        calculateAverageSpeedMetersPerSecond(
          1000,
          const Duration(seconds: 360),
        ),
        closeTo(2.7777777778, 0.0000000001),
      );
    });

    test('returns zero for invalid average-speed inputs', () {
      expect(
        calculateAverageSpeedMetersPerSecond(0, const Duration(seconds: 1)),
        0,
      );
      expect(
        calculateAverageSpeedMetersPerSecond(-1, const Duration(seconds: 1)),
        0,
      );
      expect(
        calculateAverageSpeedMetersPerSecond(
          double.nan,
          const Duration(seconds: 1),
        ),
        0,
      );
      expect(
        calculateAverageSpeedMetersPerSecond(
          double.infinity,
          const Duration(seconds: 1),
        ),
        0,
      );
      expect(calculateAverageSpeedMetersPerSecond(1, Duration.zero), 0);
      expect(
        calculateAverageSpeedMetersPerSecond(1, const Duration(seconds: -1)),
        0,
      );
    });

    test('calculates pace in fractional minutes per kilometre', () {
      expect(
        calculatePace(5000, const Duration(minutes: 25)),
        closeTo(5, 0.0000001),
      );
      expect(calculatePace(0, const Duration(minutes: 25)), isNull);
      expect(calculatePace(5000, Duration.zero), isNull);
      expect(calculatePace(double.nan, const Duration(minutes: 25)), isNull);
    });

    test('formats pace by rounding total seconds safely', () {
      expect(formatPaceMinutesPerKilometer(5), '5:00');
      expect(formatPaceMinutesPerKilometer(5.999), '6:00');
      expect(formatPaceMinutesPerKilometer(null), '--:--');
      expect(formatPaceMinutesPerKilometer(0), '--:--');
      expect(formatPaceMinutesPerKilometer(double.nan), '--:--');
      expect(formatPaceMinutesPerKilometer(double.infinity), '--:--');
    });
  });

  group('speed conversion and formatting', () {
    test('converts and formats metres per second exactly once', () {
      const speedMetersPerSecond = 2.7777777777777777;

      expect(
        metersPerSecondToKilometersPerHour(speedMetersPerSecond),
        closeTo(10, 0.0000001),
      );
      expect(
        formatMetersPerSecondAsKilometersPerHour(speedMetersPerSecond),
        '10.0 km/h',
      );
    });

    test('formats invalid canonical speed as a safe zero', () {
      expect(formatMetersPerSecondAsKilometersPerHour(0), '0.0 km/h');
      expect(formatMetersPerSecondAsKilometersPerHour(-1), '0.0 km/h');
      expect(formatMetersPerSecondAsKilometersPerHour(double.nan), '0.0 km/h');
      expect(
        formatMetersPerSecondAsKilometersPerHour(double.infinity),
        '0.0 km/h',
      );
    });
  });

  group('workout completion summary', () {
    test('stores m/s and gives the calorie estimator 10 km/h once', () {
      final summary = calculateWorkoutCompletionMetrics(
        distanceInMeters: 10000,
        activeDuration: const Duration(hours: 1),
        userWeightKilograms: 70,
      );

      expect(
        summary.averageSpeedMetersPerSecond,
        closeTo(2.7777777778, 0.0000000001),
      );
      expect(summary.averagePaceMinutesPerKilometer, closeTo(6, 0.0000001));
      expect(summary.estimatedCalories, 770);
    });

    test('returns a safe empty summary for invalid activity inputs', () {
      final summary = calculateWorkoutCompletionMetrics(
        distanceInMeters: 0,
        activeDuration: Duration.zero,
        userWeightKilograms: 70,
      );

      expect(summary.averageSpeedMetersPerSecond, 0);
      expect(summary.averagePaceMinutesPerKilometer, isNull);
      expect(summary.estimatedCalories, 0);
    });
  });
}
