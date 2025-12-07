import 'package:flutter/widgets.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';

abstract class AdsProvider {
  Future<void> initialize();

  Future<bool> preload(AdsPlacement placement) async {
    return false;
  }

  Future<AdsResult> show(AdsPlacement placement);

  Widget buildBanner(AdsPlacement placement);

  void dispose();
}
