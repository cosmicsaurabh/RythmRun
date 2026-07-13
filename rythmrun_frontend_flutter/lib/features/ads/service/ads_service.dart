import 'dart:async';

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
    Duration initializationTimeout = const Duration(seconds: 10),
    Duration showTimeout = const Duration(seconds: 45),
  }) : _config = config,
       _providerFactory = providerFactory,
       _storage = storage,
       _initializationTimeout = initializationTimeout,
       _showTimeout = showTimeout;

  final AdsConfig _config;
  final AdsProviderFactory _providerFactory;
  final AdsStorage _storage;
  final Duration _initializationTimeout;
  final Duration _showTimeout;
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
    _initialization ??= _initializeFailClosed();
    return _initialization!;
  }

  Future<void> _initializeFailClosed() async {
    try {
      await _init().timeout(_initializationTimeout);
    } catch (_) {
      final provider = _provider;
      if (provider != null) _abandonProvider(provider);
    }
  }

  Future<void> _init() async {
    if (!_adsEnabled) return;
    final provider = _providerFactory.create(_config);
    _provider = provider;
    await provider.initialize();
    if (!identical(_provider, provider)) return;
    final lastPostActivityShown = await _storage.getLastPostActivityAd();
    if (!identical(_provider, provider)) return;
    final lastStartOfDayReward = await _storage.getLastStartOfDayReward();
    if (!identical(_provider, provider)) return;
    _lastPostActivityShown = lastPostActivityShown;
    _lastStartOfDayReward = lastStartOfDayReward;
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

    final AdsResult result;
    try {
      await _ensureInitialized();
      final provider = _provider;
      if (provider == null) {
        return const AdsResult.unavailable('Start-of-day ad unavailable');
      }
      result = await provider.show(AdsPlacement.startOfDayOffer);
    } catch (_) {
      return const AdsResult.unavailable('Start-of-day ad unavailable');
    }
    if (result.isSuccess) {
      final now = DateTime.now();
      _lastStartOfDayReward = now;
      try {
        await _storage.setLastStartOfDayReward(now);
      } catch (_) {
        // Optional cooldown persistence must not escape into product flows.
      }
    }
    return result;
  }

  Future<AdsResult> showPostActivityAd({
    bool Function()? isStillEligible,
  }) async {
    if (!_adsEnabled || !_config.enablePostActivityAd) {
      return const AdsResult.unavailable('Post-activity ad disabled');
    }

    bool upstreamEligibility() => isStillEligible?.call() ?? true;
    if (!upstreamEligibility()) {
      return const AdsResult.unavailable('Post-activity ad no longer eligible');
    }

    if (isAdFreeToday) {
      return const AdsResult.unavailable('Ad-free day active');
    }

    if (!canShowPostActivityAd) {
      return const AdsResult.unavailable('Post-activity cooldown active');
    }

    final AdsResult result;
    var operationActive = true;
    bool operationEligibility() => operationActive && upstreamEligibility();
    try {
      await _ensureInitialized();
      final provider = _provider;
      if (provider == null || !operationEligibility()) {
        return const AdsResult.unavailable('Post-activity ad unavailable');
      }
      result = await provider
          .show(
            AdsPlacement.postActivityUnskippable,
            isStillEligible: operationEligibility,
          )
          .timeout(_showTimeout);
    } on TimeoutException {
      final provider = _provider;
      if (provider != null) _abandonProvider(provider);
      return const AdsResult.unavailable('Post-activity ad unavailable');
    } catch (_) {
      return const AdsResult.unavailable('Post-activity ad unavailable');
    } finally {
      operationActive = false;
    }
    if (result.isSuccess) {
      final now = DateTime.now();
      _lastPostActivityShown = now;
      try {
        await _storage.setLastPostActivityAd(now);
      } catch (_) {
        // Optional cooldown persistence must not escape into product flows.
      }
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
    final provider = _provider;
    if (provider != null) _abandonProvider(provider);
  }

  void _abandonProvider(AdsProvider provider) {
    if (identical(_provider, provider)) {
      _provider = null;
    }
    provider.dispose();
  }
}
