import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/providers/noop_ads_provider.dart';

typedef AdsProviderBuilder = AdsProvider Function(AdsConfig config);

class AdsProviderFactory {
  AdsProviderFactory({Map<AdsProviderType, AdsProviderBuilder>? builders})
    : _builders = builders ?? {};

  final Map<AdsProviderType, AdsProviderBuilder> _builders;

  void register(AdsProviderType type, AdsProviderBuilder builder) {
    _builders[type] = builder;
  }

  AdsProvider create(AdsConfig config) {
    final builder = _builders[config.providerType];
    if (builder != null) {
      return builder(config);
    }

    final fallbackBuilder = _builders[AdsProviderType.noOp];
    if (fallbackBuilder != null) {
      return fallbackBuilder(config);
    }

    return const NoOpAdsProvider();
  }
}
