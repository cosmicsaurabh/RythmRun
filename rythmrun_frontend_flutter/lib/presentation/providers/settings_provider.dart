import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../core/di/injection_container.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepository _settingsRepository;

  SettingsNotifier(this._settingsRepository) : super(const AppSettings()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final settings = await _settingsRepository.getSettings();
      state = settings;
    } catch (e) {
      // If loading fails, keep default settings
      print('Error loading settings: $e');
    }
  }

  Future<void> updateThemeMode(AppThemeMode themeMode) async {
    try {
      await _settingsRepository.updateThemeMode(themeMode);
      state = state.copyWith(themeMode: themeMode);
    } catch (e) {
      print('Error updating theme mode: $e');
    }
  }

  Future<void> updateMeasurementUnit(MeasurementUnit unit) async {
    try {
      await _settingsRepository.updateMeasurementUnit(unit);
      state = state.copyWith(measurementUnit: unit);
    } catch (e) {
      print('Error updating measurement unit: $e');
    }
  }

  Future<void> resetSettings() async {
    try {
      await _settingsRepository.clearSettings();
      state = const AppSettings();
    } catch (e) {
      print('Error resetting settings: $e');
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return SettingsNotifier(settingsRepository);
});

// Convenience providers
final themeModeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});

final measurementUnitProvider = Provider<MeasurementUnit>((ref) {
  return ref.watch(settingsProvider).measurementUnit;
});
