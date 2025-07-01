import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, system }

enum MeasurementUnit { metric, imperial }

class AppSettings {
  final AppThemeMode themeMode;
  final MeasurementUnit measurementUnit;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.measurementUnit = MeasurementUnit.metric,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    MeasurementUnit? measurementUnit,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      measurementUnit: measurementUnit ?? this.measurementUnit,
    );
  }

  // Convert to Flutter ThemeMode
  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  // JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.name,
      'measurementUnit': measurementUnit.name,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: AppThemeMode.values.firstWhere(
        (e) => e.name == json['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      measurementUnit: MeasurementUnit.values.firstWhere(
        (e) => e.name == json['measurementUnit'],
        orElse: () => MeasurementUnit.metric,
      ),
    );
  }
}
