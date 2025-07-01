import '../core/models/app_settings.dart';

class UnitConverter {
  final MeasurementUnit measurementUnit;

  const UnitConverter(this.measurementUnit);

  // Helper methods for units
  String formatDistance(double kilometers) {
    if (measurementUnit == MeasurementUnit.imperial) {
      final miles = kilometers * 0.621371;
      return '${miles.toStringAsFixed(1)} mi';
    }
    return '${kilometers.toStringAsFixed(1)} km';
  }

  String formatSpeed(double kmh) {
    if (measurementUnit == MeasurementUnit.imperial) {
      final mph = kmh * 0.621371;
      return '${mph.toStringAsFixed(1)} mph';
    }
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  String formatWeight(double kg) {
    if (measurementUnit == MeasurementUnit.imperial) {
      final lbs = kg * 2.20462;
      return '${lbs.toStringAsFixed(1)} lbs';
    }
    return '${kg.toStringAsFixed(1)} kg';
  }

  String formatHeight(double cm) {
    if (measurementUnit == MeasurementUnit.imperial) {
      final totalInches = cm / 2.54;
      final feet = (totalInches / 12).floor();
      final inches = (totalInches % 12).round();
      return '$feet\'$inches"';
    }
    return '${cm.toStringAsFixed(0)} cm';
  }
}
