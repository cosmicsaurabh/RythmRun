import '../../core/models/app_settings.dart';
import '../../core/services/settings_service.dart';
import '../../domain/repositories/settings_repository.dart';

/// Implementation of SettingsRepository using SettingsService
class SettingsRepositoryImpl implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async {
    return await SettingsService.getSettings();
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await SettingsService.saveSettings(settings);
  }

  @override
  Future<void> updateThemeMode(AppThemeMode themeMode) async {
    await SettingsService.updateThemeMode(themeMode);
  }

  @override
  Future<void> updateMeasurementUnit(MeasurementUnit unit) async {
    await SettingsService.updateMeasurementUnit(unit);
  }

  @override
  Future<void> clearSettings() async {
    await SettingsService.clearSettings();
  }
}
