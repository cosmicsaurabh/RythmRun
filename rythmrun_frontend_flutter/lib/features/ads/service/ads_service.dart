import 'package:flutter/widgets.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider_factory.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_storage.dart';

class AdsService {
  AdsService({
    required AdsConfig config,
    required AdsProviderFactory providerFactory,
    required AdsStorage storage,
  }) : _config = config,
       _providerFactory = providerFactory,
       _storage = storage;

  final AdsConfig _config;
  final AdsProviderFactory _providerFactory;
  final AdsStorage _storage;
  AdsProvider? _provider;
  Future<void>? _initialization;
  DateTime? _lastPostActivityShown;
  DateTime? _lastStartOfDayReward;

  bool get _adsEnabled => _config.adsEnabled;

  bool get isAdFreeToday {
    if (_lastStartOfDayReward == null) return false;
    return DateTime.now().difference(_lastStartOfDayReward!) <
        _config.startOfDayRewardCooldown;
  }

  Future<void> initialize() {
    _initialization ??= _init();
    return _initialization!;
  }

  Future<void> _init() async {
    if (!_adsEnabled) return;
    _provider = _providerFactory.create(_config);
    await _provider!.initialize();
    _lastPostActivityShown = await _storage.getLastPostActivityAd();
    _lastStartOfDayReward = await _storage.getLastStartOfDayReward();
  }

  Future<void> _ensureInitialized() async {
    if (_initialization == null) {
      await initialize();
    } else {
      await _initialization;
    }
  }

  Future<AdsResult> showStartOfDayOffer() async {
    if (!_adsEnabled || !_config.enableStartOfDayOffer) {
      return const AdsResult.unavailable('Start-of-day offer disabled');
    }

    if (!canShowStartOfDayOffer) {
      return const AdsResult.unavailable('Start-of-day cooldown active');
    }

    await _ensureInitialized();

    final result = await _provider!.show(AdsPlacement.startOfDayOffer);
    if (result.isSuccess) {
      final now = DateTime.now();
      _lastStartOfDayReward = now;
      await _storage.setLastStartOfDayReward(now);
    }
    return result;
  }

  Future<AdsResult> showPostActivityAd() async {
    if (!_adsEnabled || !_config.enablePostActivityAd) {
      return const AdsResult.unavailable('Post-activity ad disabled');
    }

    if (isAdFreeToday) {
      return const AdsResult.unavailable('Ad-free day active');
    }

    if (!canShowPostActivityAd) {
      return const AdsResult.unavailable('Post-activity cooldown active');
    }

    await _ensureInitialized();
    final result = await _provider!.show(AdsPlacement.postActivityUnskippable);
    if (result.isSuccess) {
      final now = DateTime.now();
      _lastPostActivityShown = now;
      await _storage.setLastPostActivityAd(now);
    }
    return result;
  }

  Widget activityBanner() {
    if (!_adsEnabled || !_config.enableActivityBanner || isAdFreeToday) {
      return const SizedBox.shrink();
    }
    initialize();
    return _provider?.buildBanner(AdsPlacement.activityBanner) ??
        const SizedBox.shrink();
  }

  bool get canShowStartOfDayOffer {
    if (!_adsEnabled || !_config.enableStartOfDayOffer) return false;
    if (_lastStartOfDayReward == null) return true;
    return DateTime.now().difference(_lastStartOfDayReward!) >=
        _config.startOfDayRewardCooldown;
  }

  bool get canShowPostActivityAd {
    if (!_adsEnabled || !_config.enablePostActivityAd || isAdFreeToday) {
      return false;
    }
    if (_lastPostActivityShown == null) return true;
    return DateTime.now().difference(_lastPostActivityShown!) >=
        _config.postActivityCooldown;
  }

  void dispose() {
    _provider?.dispose();
  }
}
