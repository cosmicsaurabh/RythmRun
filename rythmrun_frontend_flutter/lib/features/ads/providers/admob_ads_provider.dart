import 'dart:async';
import 'dart:io';

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

  @override
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    await Future.wait([_loadRewardedAd(), _loadInterstitialAd()]);
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
  Future<AdsResult> show(AdsPlacement placement) {
    switch (placement) {
      case AdsPlacement.startOfDayOffer:
        return _showRewardedAd();
      case AdsPlacement.postActivityUnskippable:
        return _showInterstitialAd();
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
    _startOfDayRewardedAd?.dispose();
    _postActivityInterstitialAd?.dispose();
  }

  Future<bool> _loadRewardedAd() async {
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

  Future<AdsResult> _showRewardedAd() async {
    if (_startOfDayRewardedAd == null) {
      final loaded = await _loadRewardedAd();
      if (!loaded || _startOfDayRewardedAd == null) {
        return const AdsResult.unavailable('Rewarded ad unavailable');
      }
    }

    final completer = Completer<AdsResult>();
    var rewardEarned = false;
    final rewardedAd = _startOfDayRewardedAd!;

    rewardedAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _startOfDayRewardedAd = null;
        _loadRewardedAd();
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
        _loadRewardedAd();
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

  Future<AdsResult> _showInterstitialAd() async {
    if (_postActivityInterstitialAd == null) {
      final loaded = await _loadInterstitialAd();
      if (!loaded || _postActivityInterstitialAd == null) {
        return const AdsResult.unavailable('Interstitial ad unavailable');
      }
    }

    final completer = Completer<AdsResult>();
    final interstitialAd = _postActivityInterstitialAd!;

    interstitialAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _postActivityInterstitialAd = null;
        _loadInterstitialAd();
        completer.complete(const AdsResult.completed());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _postActivityInterstitialAd = null;
        _loadInterstitialAd();
        completer.complete(AdsResult.failed(error.message));
      },
    );

    interstitialAd.show();
    return completer.future;
  }

  String? _adUnitIdFor(AdsPlacement placement) {
    final configUnitId = _config.adUnitFor(placement);
    if (configUnitId != null && configUnitId.isNotEmpty) {
      return configUnitId;
    }

    final isAndroid = Platform.isAndroid;
    return switch (placement) {
      AdsPlacement.startOfDayOffer =>
        isAndroid
            ? 'ca-app-pub-9575153117176686/1433176172'
            : 'ca-app-pub-3940256099942544/1712485313', // iOS test ID - replace when you have iOS
      AdsPlacement.postActivityUnskippable =>
        isAndroid
            ? 'ca-app-pub-9575153117176686/9279876606'
            : 'ca-app-pub-3940256099942544/4411468910', // iOS test ID - replace when you have iOS
      AdsPlacement.activityBanner =>
        isAndroid
            ? 'ca-app-pub-9575153117176686/5180849497'
            : 'ca-app-pub-3940256099942544/2934735716', // iOS test ID - replace when you have iOS
    };
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
