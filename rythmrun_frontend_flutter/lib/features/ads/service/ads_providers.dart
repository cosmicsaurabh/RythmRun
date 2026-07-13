import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_build_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider_factory.dart';
import 'package:rythmrun_frontend_flutter/features/ads/providers/admob_ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/providers/noop_ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_service.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_storage.dart';

final adsConfigProvider = Provider<AdsConfig>((ref) {
  return AdsBuildConfig.current();
});

final adsProviderFactoryProvider = Provider<AdsProviderFactory>((ref) {
  final factory = AdsProviderFactory();
  factory
    ..register(AdsProviderType.noOp, (_) => const NoOpAdsProvider())
    ..register(
      AdsProviderType.admob,
      (config) => AdmobAdsProvider(config: config),
    );
  return factory;
});

final adsStorageProvider = Provider<AdsStorage>((ref) {
  return SharedPrefsAdsStorage();
});

final adsServiceProvider = Provider<AdsService>((ref) {
  final config = ref.watch(adsConfigProvider);
  final factory = ref.watch(adsProviderFactoryProvider);
  final storage = ref.watch(adsStorageProvider);
  final service = AdsService(
    config: config,
    providerFactory: factory,
    storage: storage,
  );
  ref.onDispose(service.dispose);
  return service;
});
