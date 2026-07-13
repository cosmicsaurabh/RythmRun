import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';

class AdmobAdsProvider implements AdsProvider {
  AdmobAdsProvider({required AdsConfig config}) : _config = config;

  final AdsConfig _config;

  RewardedAd? _startOfDayRewardedAd;
  InterstitialAd? _postActivityInterstitialAd;

  bool _isLoadingRewarded = false;
  bool _isLoadingInterstitial = false;
  bool _isDisposed = false;

  @override
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  @override
  Future<bool> preload(AdsPlacement placement) async {
    switch (placement) {
      case AdsPlacement.startOfDayOffer:
        return _loadRewardedAd();
      case AdsPlacement.postActivityUnskippable:
        return _loadInterstitialAd();
      case AdsPlacement.activityBanner:
        return true;
    }
  }

  @override
  Future<AdsResult> show(
    AdsPlacement placement, {
    bool Function()? isStillEligible,
  }) {
    switch (placement) {
      case AdsPlacement.startOfDayOffer:
        return _showRewardedAd(isStillEligible);
      case AdsPlacement.postActivityUnskippable:
        return _showInterstitialAd(isStillEligible);
      case AdsPlacement.activityBanner:
        return Future.value(
          const AdsResult.unavailable('Use buildBanner for banner placements'),
        );
    }
  }

  @override
  Widget buildBanner(AdsPlacement placement) {
    final adUnitId = _adUnitIdFor(placement);
    if (adUnitId == null) {
      return const SizedBox.shrink();
    }

    return _AdmobBannerView(adUnitId: adUnitId);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _startOfDayRewardedAd?.dispose();
    _startOfDayRewardedAd = null;
    _postActivityInterstitialAd?.dispose();
    _postActivityInterstitialAd = null;
  }

  Future<bool> _loadRewardedAd() async {
    if (_isDisposed) return false;
    if (_isLoadingRewarded) return _startOfDayRewardedAd != null;
    final adUnitId = _adUnitIdFor(AdsPlacement.startOfDayOffer);
    if (adUnitId == null) return false;
    _isLoadingRewarded = true;
    final completer = Completer<bool>();

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (_isDisposed) {
            ad.dispose();
            _isLoadingRewarded = false;
            completer.complete(false);
            return;
          }
          _startOfDayRewardedAd = ad;
          _isLoadingRewarded = false;
          completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _startOfDayRewardedAd?.dispose();
          _startOfDayRewardedAd = null;
          _isLoadingRewarded = false;
          completer.complete(false);
        },
      ),
    );
    return completer.future;
  }

  Future<bool> _loadInterstitialAd() async {
    if (_isDisposed) return false;
    if (_isLoadingInterstitial) return _postActivityInterstitialAd != null;
    final adUnitId = _adUnitIdFor(AdsPlacement.postActivityUnskippable);
    if (adUnitId == null) return false;
    _isLoadingInterstitial = true;
    final completer = Completer<bool>();

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (_isDisposed) {
            ad.dispose();
            _isLoadingInterstitial = false;
            completer.complete(false);
            return;
          }
          _postActivityInterstitialAd = ad;
          _isLoadingInterstitial = false;
          completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _postActivityInterstitialAd?.dispose();
          _postActivityInterstitialAd = null;
          _isLoadingInterstitial = false;
          completer.complete(false);
        },
      ),
    );
    return completer.future;
  }

  Future<AdsResult> _showRewardedAd(bool Function()? isStillEligible) async {
    if (!_canContinue(isStillEligible)) {
      return const AdsResult.unavailable('Rewarded ad no longer eligible');
    }
    if (_startOfDayRewardedAd == null) {
      final loaded = await _loadRewardedAd();
      if (!loaded || _startOfDayRewardedAd == null) {
        return const AdsResult.unavailable('Rewarded ad unavailable');
      }
    }
    if (!_canContinue(isStillEligible)) {
      _startOfDayRewardedAd?.dispose();
      _startOfDayRewardedAd = null;
      return const AdsResult.unavailable('Rewarded ad no longer eligible');
    }

    final completer = Completer<AdsResult>();
    var rewardEarned = false;
    final rewardedAd = _startOfDayRewardedAd!;

    rewardedAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _startOfDayRewardedAd = null;
        if (!_isDisposed) _loadRewardedAd();
        if (!completer.isCompleted) {
          completer.complete(
            rewardEarned
                ? const AdsResult.completed()
                : const AdsResult.skipped(),
          );
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _startOfDayRewardedAd = null;
        if (!_isDisposed) _loadRewardedAd();
        if (!completer.isCompleted) {
          completer.complete(AdsResult.failed(error.message));
        }
      },
    );

    rewardedAd.show(
      onUserEarnedReward: (adWithoutView, reward) {
        rewardEarned = true;
      },
    );

    return completer.future;
  }

  Future<AdsResult> _showInterstitialAd(
    bool Function()? isStillEligible,
  ) async {
    if (!_canContinue(isStillEligible)) {
      return const AdsResult.unavailable('Post-activity ad no longer eligible');
    }
    if (_postActivityInterstitialAd == null) {
      final loaded = await _loadInterstitialAd();
      if (!loaded || _postActivityInterstitialAd == null) {
        return const AdsResult.unavailable('Interstitial ad unavailable');
      }
    }
    if (!_canContinue(isStillEligible)) {
      _postActivityInterstitialAd?.dispose();
      _postActivityInterstitialAd = null;
      return const AdsResult.unavailable('Post-activity ad no longer eligible');
    }

    final completer = Completer<AdsResult>();
    final interstitialAd = _postActivityInterstitialAd!;

    interstitialAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _postActivityInterstitialAd = null;
        if (!_isDisposed) _loadInterstitialAd();
        if (!completer.isCompleted) {
          completer.complete(const AdsResult.completed());
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _postActivityInterstitialAd = null;
        if (!_isDisposed) _loadInterstitialAd();
        if (!completer.isCompleted) {
          completer.complete(AdsResult.failed(error.message));
        }
      },
    );

    interstitialAd.show();
    return completer.future;
  }

  bool _canContinue(bool Function()? isStillEligible) {
    return !_isDisposed && (isStillEligible?.call() ?? true);
  }

  String? _adUnitIdFor(AdsPlacement placement) {
    final configUnitId = _config.adUnitFor(placement)?.trim();
    return configUnitId == null || configUnitId.isEmpty ? null : configUnitId;
  }
}

class _AdmobBannerView extends StatefulWidget {
  const _AdmobBannerView({required this.adUnitId});

  final String adUnitId;

  @override
  State<_AdmobBannerView> createState() => _AdmobBannerViewState();
}

class _AdmobBannerViewState extends State<_AdmobBannerView> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    final banner = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() {
            _isLoaded = false;
          });
        },
      ),
    )..load();

    _bannerAd = banner;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    final ad = _bannerAd!;
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
