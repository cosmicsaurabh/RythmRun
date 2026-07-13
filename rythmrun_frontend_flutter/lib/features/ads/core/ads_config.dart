import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';

enum AdsProviderType { noOp, admob, unity, ironSource }

class AdsConfig {
  const AdsConfig({
    this.adsEnabled = false,
    this.enableStartOfDayOffer = false,
    this.enablePostActivityAd = false,
    this.enableActivityBanner = false,
    this.postActivityCooldown = const Duration(minutes: 15),
    this.startOfDayRewardCooldown = const Duration(hours: 24),
    this.providerType = AdsProviderType.noOp,
    this.adUnitIds = const {},
  });

  final bool adsEnabled;
  final bool enableStartOfDayOffer;
  final bool enablePostActivityAd;
  final bool enableActivityBanner;
  final Duration postActivityCooldown;
  final Duration startOfDayRewardCooldown;
  final AdsProviderType providerType;
  final Map<AdsPlacement, String> adUnitIds;

  AdsConfig copyWith({
    bool? adsEnabled,
    bool? enableStartOfDayOffer,
    bool? enablePostActivityAd,
    bool? enableActivityBanner,
    Duration? postActivityCooldown,
    Duration? startOfDayRewardCooldown,
    AdsProviderType? providerType,
    Map<AdsPlacement, String>? adUnitIds,
  }) {
    return AdsConfig(
      adsEnabled: adsEnabled ?? this.adsEnabled,
      enableStartOfDayOffer:
          enableStartOfDayOffer ?? this.enableStartOfDayOffer,
      enablePostActivityAd: enablePostActivityAd ?? this.enablePostActivityAd,
      enableActivityBanner: enableActivityBanner ?? this.enableActivityBanner,
      postActivityCooldown: postActivityCooldown ?? this.postActivityCooldown,
      startOfDayRewardCooldown:
          startOfDayRewardCooldown ?? this.startOfDayRewardCooldown,
      providerType: providerType ?? this.providerType,
      adUnitIds: adUnitIds ?? this.adUnitIds,
    );
  }

  String? adUnitFor(AdsPlacement placement) => adUnitIds[placement];

  static const AdsConfig disabled = AdsConfig();

  static AdsConfig postActivityAdmob({required String adUnitId}) {
    return AdsConfig(
      adsEnabled: true,
      enablePostActivityAd: true,
      providerType: AdsProviderType.admob,
      adUnitIds: {AdsPlacement.postActivityUnskippable: adUnitId},
    );
  }

  static AdsConfig defaults() => disabled;
}
