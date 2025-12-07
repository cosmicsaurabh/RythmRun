import 'package:shared_preferences/shared_preferences.dart';

abstract class AdsStorage {
  Future<DateTime?> getLastStartOfDayReward();
  Future<void> setLastStartOfDayReward(DateTime dateTime);

  Future<DateTime?> getLastPostActivityAd();
  Future<void> setLastPostActivityAd(DateTime dateTime);
}

class SharedPrefsAdsStorage implements AdsStorage {
  static const _startOfDayKey = 'ads_last_start_of_day_reward';
  static const _postActivityKey = 'ads_last_post_activity_ad';

  static SharedPreferences? _prefs;

  Future<SharedPreferences> get _prefsInstance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<DateTime?> getLastStartOfDayReward() async {
    final prefs = await _prefsInstance;
    final millis = prefs.getInt(_startOfDayKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<void> setLastStartOfDayReward(DateTime dateTime) async {
    final prefs = await _prefsInstance;
    await prefs.setInt(_startOfDayKey, dateTime.millisecondsSinceEpoch);
  }

  @override
  Future<DateTime?> getLastPostActivityAd() async {
    final prefs = await _prefsInstance;
    final millis = prefs.getInt(_postActivityKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<void> setLastPostActivityAd(DateTime dateTime) async {
    final prefs = await _prefsInstance;
    await prefs.setInt(_postActivityKey, dateTime.millisecondsSinceEpoch);
  }
}
