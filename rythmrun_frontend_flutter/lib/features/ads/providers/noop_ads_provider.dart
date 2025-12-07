import 'package:flutter/widgets.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';

class NoOpAdsProvider implements AdsProvider {
  const NoOpAdsProvider();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> preload(AdsPlacement placement) async {
    return false;
  }

  @override
  Future<AdsResult> show(AdsPlacement placement) async {
    return const AdsResult.unavailable('Ads disabled');
  }

  @override
  Widget buildBanner(AdsPlacement placement) {
    return const SizedBox.shrink();
  }

  @override
  void dispose() {}
}
