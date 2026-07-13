import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider_factory.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';
import 'package:rythmrun_frontend_flutter/features/ads/providers/noop_ads_provider.dart';

void main() {
  group('AdsProviderFactory', () {
    test('disabled config never constructs its requested live provider', () {
      var admobBuilds = 0;
      var noOpBuilds = 0;
      final noOp = _FakeAdsProvider();
      final factory =
          AdsProviderFactory()
            ..register(AdsProviderType.admob, (_) {
              admobBuilds += 1;
              return _FakeAdsProvider();
            })
            ..register(AdsProviderType.noOp, (_) {
              noOpBuilds += 1;
              return noOp;
            });

      final provider = factory.create(
        const AdsConfig(adsEnabled: false, providerType: AdsProviderType.admob),
      );

      expect(provider, same(noOp));
      expect(admobBuilds, 0);
      expect(noOpBuilds, 1);
    });

    test('uses a registered provider only when ads are enabled', () {
      final admob = _FakeAdsProvider();
      final factory =
          AdsProviderFactory()..register(AdsProviderType.admob, (_) => admob);

      final provider = factory.create(
        const AdsConfig(adsEnabled: true, providerType: AdsProviderType.admob),
      );

      expect(provider, same(admob));
    });

    test('unknown enabled providers fail closed to registered no-op', () {
      var noOpBuilds = 0;
      final noOp = _FakeAdsProvider();
      final factory =
          AdsProviderFactory()..register(AdsProviderType.noOp, (_) {
            noOpBuilds += 1;
            return noOp;
          });

      final provider = factory.create(
        const AdsConfig(adsEnabled: true, providerType: AdsProviderType.unity),
      );

      expect(provider, same(noOp));
      expect(noOpBuilds, 1);
    });

    test('uses the built-in no-op when no fallback is registered', () {
      final provider = AdsProviderFactory().create(
        const AdsConfig(
          adsEnabled: true,
          providerType: AdsProviderType.ironSource,
        ),
      );

      expect(provider, isA<NoOpAdsProvider>());
    });
  });
}

class _FakeAdsProvider implements AdsProvider {
  @override
  Widget buildBanner(AdsPlacement placement) => const SizedBox.shrink();

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> preload(AdsPlacement placement) async => false;

  @override
  Future<AdsResult> show(
    AdsPlacement placement, {
    bool Function()? isStillEligible,
  }) async {
    return const AdsResult.unavailable();
  }
}
