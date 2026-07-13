import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_build_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';

void main() {
  const appId = 'ca-app-pub-1234567890123456~1234567890';
  const postActivityUnitId = 'ca-app-pub-1234567890123456/0987654321';

  AdsBuildSettings settings({
    String environment = 'development',
    bool productionAdsEnabled = false,
    bool isReleaseMode = false,
    bool isAndroid = true,
    String androidAppId = '',
    String postActivityAdUnitId = '',
  }) {
    return AdsBuildSettings(
      environment: environment,
      productionAdsEnabled: productionAdsEnabled,
      isReleaseMode: isReleaseMode,
      isAndroid: isAndroid,
      androidAppId: androidAppId,
      postActivityAdUnitId: postActivityAdUnitId,
    );
  }

  void expectDisabled(AdsConfig config) {
    expect(config.adsEnabled, isFalse);
    expect(config.providerType, AdsProviderType.noOp);
    expect(config.enableStartOfDayOffer, isFalse);
    expect(config.enablePostActivityAd, isFalse);
    expect(config.enableActivityBanner, isFalse);
    expect(config.adUnitIds, isEmpty);
  }

  group('AdsBuildConfig.resolve', () {
    test('defaults to a disabled no-op configuration', () {
      expectDisabled(AdsBuildConfig.resolve(settings()));
    });

    test('development and staging never resolve production IDs', () {
      for (final environment in ['development', 'staging']) {
        final config = AdsBuildConfig.resolve(
          settings(
            environment: environment,
            productionAdsEnabled: true,
            isReleaseMode: true,
            androidAppId: appId,
            postActivityAdUnitId: postActivityUnitId,
          ),
        );

        expectDisabled(config);
      }
    });

    test('a disabled production release does not validate or expose IDs', () {
      final config = AdsBuildConfig.resolve(
        settings(
          environment: 'production',
          isReleaseMode: true,
          androidAppId: 'malformed-but-unused',
          postActivityAdUnitId: 'malformed-but-unused',
        ),
      );

      expectDisabled(config);
    });

    test('keeps production configuration disabled outside release mode', () {
      final config = AdsBuildConfig.resolve(
        settings(
          environment: 'production',
          productionAdsEnabled: true,
          androidAppId: appId,
          postActivityAdUnitId: postActivityUnitId,
        ),
      );

      expectDisabled(config);
    });

    test('keeps unsupported release platforms disabled', () {
      final config = AdsBuildConfig.resolve(
        settings(
          environment: 'production',
          productionAdsEnabled: true,
          isReleaseMode: true,
          isAndroid: false,
          androidAppId: appId,
          postActivityAdUnitId: postActivityUnitId,
        ),
      );

      expectDisabled(config);
    });

    test('enables only the post-activity placement for valid Android IDs', () {
      final config = AdsBuildConfig.resolve(
        settings(
          environment: ' PRODUCTION ',
          productionAdsEnabled: true,
          isReleaseMode: true,
          androidAppId: ' $appId ',
          postActivityAdUnitId: ' $postActivityUnitId ',
        ),
      );

      expect(config.adsEnabled, isTrue);
      expect(config.providerType, AdsProviderType.admob);
      expect(config.enableStartOfDayOffer, isFalse);
      expect(config.enablePostActivityAd, isTrue);
      expect(config.enableActivityBanner, isFalse);
      expect(
        config.adUnitFor(AdsPlacement.postActivityUnskippable),
        postActivityUnitId,
      );
      expect(config.adUnitIds, hasLength(1));
    });

    test('rejects missing or malformed production IDs', () {
      final invalidPairs = <(String, String)>[
        ('', postActivityUnitId),
        (appId, ''),
        ('ca-app-pub-123~123', postActivityUnitId),
        (appId, 'ca-app-pub-123/123'),
      ];

      for (final (invalidAppId, invalidUnitId) in invalidPairs) {
        expect(
          () => AdsBuildConfig.resolve(
            settings(
              environment: 'production',
              productionAdsEnabled: true,
              isReleaseMode: true,
              androidAppId: invalidAppId,
              postActivityAdUnitId: invalidUnitId,
            ),
          ),
          throwsA(isA<StateError>()),
        );
      }
    });

    test('rejects Google sample IDs and publisher mismatches', () {
      const googleSampleAppId = 'ca-app-pub-3940256099942544~3347511713';
      const googleSampleUnitId = 'ca-app-pub-3940256099942544/1033173712';
      const otherPublisherUnitId = 'ca-app-pub-9999999999999999/0987654321';

      for (final (invalidAppId, invalidUnitId) in [
        (googleSampleAppId, googleSampleUnitId),
        (appId, otherPublisherUnitId),
      ]) {
        expect(
          () => AdsBuildConfig.resolve(
            settings(
              environment: 'production',
              productionAdsEnabled: true,
              isReleaseMode: true,
              androidAppId: invalidAppId,
              postActivityAdUnitId: invalidUnitId,
            ),
          ),
          throwsA(isA<StateError>()),
        );
      }
    });

    test('rejects unknown environment names even when ads are disabled', () {
      expect(
        () => AdsBuildConfig.resolve(settings(environment: 'preview')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
