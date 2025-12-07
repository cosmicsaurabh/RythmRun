enum AdsPlacement { startOfDayOffer, postActivityUnskippable, activityBanner }

extension AdsPlacementX on AdsPlacement {
  bool get requiresReward => switch (this) {
    AdsPlacement.startOfDayOffer => true,
    _ => false,
  };

  bool get isFullscreen => switch (this) {
    AdsPlacement.activityBanner => false,
    _ => true,
  };
}
