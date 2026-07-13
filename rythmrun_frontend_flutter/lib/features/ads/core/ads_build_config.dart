import 'package:flutter/foundation.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';

enum AdsEnvironment { development, staging, production }

bool _parseProductionAdsEnabled(String value) {
  return switch (value) {
    'true' => true,
    'false' => false,
    _ => throw StateError('ADS_ENABLED must be true or false.'),
  };
}

class AdsBuildSettings {
  const AdsBuildSettings({
    required this.environment,
    required this.productionAdsEnabled,
    required this.isReleaseMode,
    required this.isAndroid,
    this.androidAppId = '',
    this.postActivityAdUnitId = '',
  });

  final String environment;
  final bool productionAdsEnabled;
  final bool isReleaseMode;
  final bool isAndroid;
  final String androidAppId;
  final String postActivityAdUnitId;

  factory AdsBuildSettings.current() {
    return AdsBuildSettings(
      environment: const String.fromEnvironment(
        'ADS_ENV',
        defaultValue: 'development',
      ),
      productionAdsEnabled: _parseProductionAdsEnabled(
        const String.fromEnvironment('ADS_ENABLED', defaultValue: 'false'),
      ),
      isReleaseMode: kReleaseMode,
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      androidAppId: const String.fromEnvironment('ADMOB_ANDROID_APP_ID'),
      postActivityAdUnitId: const String.fromEnvironment(
        'ADMOB_POST_ACTIVITY_UNIT_ID',
      ),
    );
  }
}

class AdsBuildConfig {
  const AdsBuildConfig._();

  static const String googleTestPublisherId = '3940256099942544';

  static AdsConfig current() => resolve(AdsBuildSettings.current());

  static AdsConfig resolve(AdsBuildSettings settings) {
    final environment = _parseEnvironment(settings.environment);

    if (!settings.productionAdsEnabled ||
        environment != AdsEnvironment.production) {
      return AdsConfig.disabled;
    }

    // Android is the only supported ads target until the IP-5 release work
    // completes the iOS configuration and consent path.
    if (!settings.isAndroid) {
      return AdsConfig.disabled;
    }

    // Debug, profile, and test code must remain no-op even when a release
    // configuration is accidentally supplied to the build command.
    if (!settings.isReleaseMode) {
      return AdsConfig.disabled;
    }

    final appId = settings.androidAppId.trim();
    final postActivityUnitId = settings.postActivityAdUnitId.trim();
    final appPublisherId = _publisherId(
      appId,
      separator: '~',
      settingName: 'ADMOB_ANDROID_APP_ID',
    );
    final unitPublisherId = _publisherId(
      postActivityUnitId,
      separator: '/',
      settingName: 'ADMOB_POST_ACTIVITY_UNIT_ID',
    );

    if (appPublisherId == googleTestPublisherId ||
        unitPublisherId == googleTestPublisherId) {
      throw StateError('Production ads cannot use Google sample IDs.');
    }
    if (appPublisherId != unitPublisherId) {
      throw StateError(
        'AdMob application and unit IDs must use the same publisher.',
      );
    }

    // Pre-workout reward and banner placements stay disabled until IP-5.5
    // supplies consent and placement-policy gates.
    return AdsConfig.postActivityAdmob(adUnitId: postActivityUnitId);
  }

  static AdsEnvironment _parseEnvironment(String value) {
    return switch (value.trim().toLowerCase()) {
      'development' => AdsEnvironment.development,
      'staging' => AdsEnvironment.staging,
      'production' => AdsEnvironment.production,
      _ =>
        throw StateError(
          'ADS_ENV must be development, staging, or production.',
        ),
    };
  }

  static String _publisherId(
    String value, {
    required String separator,
    required String settingName,
  }) {
    final escapedSeparator = RegExp.escape(separator);
    final match = RegExp(
      '^ca-app-pub-([0-9]{16})$escapedSeparator[0-9]{10}\$',
    ).firstMatch(value);
    if (match == null) {
      throw StateError('$settingName is missing or malformed.');
    }
    return match.group(1)!;
  }
}
