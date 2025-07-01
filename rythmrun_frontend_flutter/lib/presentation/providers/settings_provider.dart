import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_settings.dart';
import '../../core/services/settings_service.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final settings = await SettingsService.getSettings();
      state = settings;
    } catch (e) {
      // If loading fails, keep default settings
      print('Error loading settings: $e');
    }
  }

  Future<void> updateThemeMode(AppThemeMode themeMode) async {
    try {
      await SettingsService.updateThemeMode(themeMode);
      state = state.copyWith(themeMode: themeMode);
    } catch (e) {
      print('Error updating theme mode: $e');
    }
  }

  Future<void> updateMeasurementUnit(MeasurementUnit unit) async {
    try {
      await SettingsService.updateMeasurementUnit(unit);
      state = state.copyWith(measurementUnit: unit);
    } catch (e) {
      print('Error updating measurement unit: $e');
    }
  }

  Future<void> resetSettings() async {
    try {
      await SettingsService.clearSettings();
      state = const AppSettings();
    } catch (e) {
      print('Error resetting settings: $e');
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});

// Convenience providers
final themeModeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});

final measurementUnitProvider = Provider<MeasurementUnit>((ref) {
  return ref.watch(settingsProvider).measurementUnit;
});
