import '../../../core/models/app_settings.dart';

abstract class SettingsRepository {
  /// Get current settings
  Future<AppSettings> getSettings();

  /// Save settings
  Future<void> saveSettings(AppSettings settings);

  /// Update theme mode
  Future<void> updateThemeMode(AppThemeMode themeMode);

  /// Update measurement unit
  Future<void> updateMeasurementUnit(MeasurementUnit unit);

  /// Clear all settings (reset to defaults)
  Future<void> clearSettings();
}
