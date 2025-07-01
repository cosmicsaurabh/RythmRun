import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';
  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<AppSettings> getSettings() async {
    await initialize();
    final settingsJson = _prefs?.getString(_settingsKey);

    if (settingsJson != null) {
      try {
        final Map<String, dynamic> json = jsonDecode(settingsJson);
        return AppSettings.fromJson(json);
      } catch (e) {
        // If parsing fails, return default settings
        return const AppSettings();
      }
    }

    return const AppSettings();
  }

  static Future<void> saveSettings(AppSettings settings) async {
    await initialize();
    final settingsJson = jsonEncode(settings.toJson());
    await _prefs?.setString(_settingsKey, settingsJson);
  }

  static Future<void> updateThemeMode(AppThemeMode themeMode) async {
    final settings = await getSettings();
    final updatedSettings = settings.copyWith(themeMode: themeMode);
    await saveSettings(updatedSettings);
  }

  static Future<void> updateMeasurementUnit(MeasurementUnit unit) async {
    final settings = await getSettings();
    final updatedSettings = settings.copyWith(measurementUnit: unit);
    await saveSettings(updatedSettings);
  }

  static Future<void> clearSettings() async {
    await initialize();
    await _prefs?.remove(_settingsKey);
  }
}
