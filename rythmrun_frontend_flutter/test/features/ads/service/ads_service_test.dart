import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_config.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_placement.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_provider_factory.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_service.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_storage.dart';

void main() {
  group('AdsService fail-closed behavior', () {
    test(
      'disabled initialization does not construct provider or read storage',
      () async {
        var providerBuilds = 0;
        final provider = _RecordingAdsProvider();
        final storage = _RecordingAdsStorage();
        final factory =
            AdsProviderFactory()..register(AdsProviderType.noOp, (_) {
              providerBuilds += 1;
              return provider;
            });
        final service = AdsService(
          config: AdsConfig.disabled,
          providerFactory: factory,
          storage: storage,
        );

        await service.initialize();
        await service.initialize();

        expect(providerBuilds, 0);
        expect(provider.initializeCalls, 0);
        expect(storage.readCalls, 0);
      },
    );

    test(
      'disabled placements return unavailable without side effects',
      () async {
        var providerBuilds = 0;
        final storage = _RecordingAdsStorage();
        final factory =
            AdsProviderFactory()..register(AdsProviderType.noOp, (_) {
              providerBuilds += 1;
              return _RecordingAdsProvider();
            });
        final service = AdsService(
          config: AdsConfig.disabled,
          providerFactory: factory,
          storage: storage,
        );

        final startResult = await service.showStartOfDayOffer();
        final postResult = await service.showPostActivityAd();
        final banner = service.activityBanner();

        expect(startResult.status, AdsResultStatus.unavailable);
        expect(postResult.status, AdsResultStatus.unavailable);
        expect(banner, isA<SizedBox>());
        expect(service.canShowStartOfDayOffer, isFalse);
        expect(service.canShowPostActivityAd, isFalse);
        expect(providerBuilds, 0);
        expect(storage.readCalls, 0);
        expect(storage.writeCalls, 0);
      },
    );

    test(
      'provider initialization failure becomes an unavailable result',
      () async {
        final provider = _RecordingAdsProvider(throwOnInitialize: true);
        final storage = _RecordingAdsStorage();
        final factory =
            AdsProviderFactory()
              ..register(AdsProviderType.admob, (_) => provider);
        final service = AdsService(
          config: AdsConfig.postActivityAdmob(
            adUnitId: 'ca-app-pub-1234567890123456/0987654321',
          ),
          providerFactory: factory,
          storage: storage,
        );

        final result = await service.showPostActivityAd();

        expect(result.status, AdsResultStatus.unavailable);
        expect(provider.initializeCalls, 1);
        expect(provider.showCalls, 0);
        expect(storage.readCalls, 0);
        expect(storage.writeCalls, 0);
      },
    );

    test('cooldown storage failure cannot fail a completed ad', () async {
      final provider = _RecordingAdsProvider();
      final storage = _RecordingAdsStorage(throwOnWrite: true);
      final factory =
          AdsProviderFactory()
            ..register(AdsProviderType.admob, (_) => provider);
      final service = AdsService(
        config: AdsConfig.postActivityAdmob(
          adUnitId: 'ca-app-pub-1234567890123456/0987654321',
        ),
        providerFactory: factory,
        storage: storage,
      );

      final result = await service.showPostActivityAd();

      expect(result.status, AdsResultStatus.completed);
      expect(provider.showCalls, 1);
      expect(storage.writeCalls, 1);
      expect(service.canShowPostActivityAd, isFalse);
    });

    test('scope change during initialization prevents provider show', () async {
      final initializationCompleter = Completer<void>();
      final provider = _RecordingAdsProvider(
        initializationCompleter: initializationCompleter,
      );
      final factory =
          AdsProviderFactory()
            ..register(AdsProviderType.admob, (_) => provider);
      final service = AdsService(
        config: AdsConfig.postActivityAdmob(
          adUnitId: 'ca-app-pub-1234567890123456/0987654321',
        ),
        providerFactory: factory,
        storage: _RecordingAdsStorage(),
      );
      var isEligible = true;

      final pendingResult = service.showPostActivityAd(
        isStillEligible: () => isEligible,
      );
      await _flushAsyncWork();
      expect(provider.initializeCalls, 1);

      isEligible = false;
      initializationCompleter.complete();
      final result = await pendingResult;

      expect(result.status, AdsResultStatus.unavailable);
      expect(provider.showCalls, 0);
      expect(provider.displayCalls, 0);
    });

    test('initialization timeout releases completion handling', () async {
      final provider = _RecordingAdsProvider(
        initializationCompleter: Completer<void>(),
      );
      final factory =
          AdsProviderFactory()
            ..register(AdsProviderType.admob, (_) => provider);
      final service = AdsService(
        config: AdsConfig.postActivityAdmob(
          adUnitId: 'ca-app-pub-1234567890123456/0987654321',
        ),
        providerFactory: factory,
        storage: _RecordingAdsStorage(),
        initializationTimeout: const Duration(milliseconds: 10),
      );

      final result = await service.showPostActivityAd();

      expect(result.status, AdsResultStatus.unavailable);
      expect(provider.initializeCalls, 1);
      expect(provider.showCalls, 0);
      expect(provider.isDisposed, isTrue);
    });

    test('show timeout prevents a late provider display', () async {
      final showCompleter = Completer<void>();
      final provider = _RecordingAdsProvider(showCompleter: showCompleter);
      final factory =
          AdsProviderFactory()
            ..register(AdsProviderType.admob, (_) => provider);
      final service = AdsService(
        config: AdsConfig.postActivityAdmob(
          adUnitId: 'ca-app-pub-1234567890123456/0987654321',
        ),
        providerFactory: factory,
        storage: _RecordingAdsStorage(),
        showTimeout: const Duration(milliseconds: 10),
      );

      final result = await service.showPostActivityAd();

      expect(result.status, AdsResultStatus.unavailable);
      expect(provider.showCalls, 1);
      expect(provider.displayCalls, 0);
      expect(provider.isDisposed, isTrue);

      showCompleter.complete();
      await _flushAsyncWork();
      expect(provider.displayCalls, 0);
    });
  });
}

class _RecordingAdsProvider implements AdsProvider {
  _RecordingAdsProvider({
    this.throwOnInitialize = false,
    this.initializationCompleter,
    this.showCompleter,
  });

  final bool throwOnInitialize;
  final Completer<void>? initializationCompleter;
  final Completer<void>? showCompleter;
  int initializeCalls = 0;
  int showCalls = 0;
  int displayCalls = 0;
  bool isDisposed = false;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    await initializationCompleter?.future;
    if (throwOnInitialize) {
      throw StateError('initialization failed');
    }
  }

  @override
  Future<bool> preload(AdsPlacement placement) async => false;

  @override
  Future<AdsResult> show(
    AdsPlacement placement, {
    bool Function()? isStillEligible,
  }) async {
    showCalls += 1;
    await showCompleter?.future;
    if (!(isStillEligible?.call() ?? true)) {
      return const AdsResult.unavailable('No longer eligible');
    }
    displayCalls += 1;
    return const AdsResult.completed();
  }

  @override
  Widget buildBanner(AdsPlacement placement) => const SizedBox.shrink();

  @override
  void dispose() {
    isDisposed = true;
  }
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _RecordingAdsStorage implements AdsStorage {
  _RecordingAdsStorage({this.throwOnWrite = false});

  final bool throwOnWrite;
  int readCalls = 0;
  int writeCalls = 0;

  @override
  Future<DateTime?> getLastPostActivityAd() async {
    readCalls += 1;
    return null;
  }

  @override
  Future<DateTime?> getLastStartOfDayReward() async {
    readCalls += 1;
    return null;
  }

  @override
  Future<void> setLastPostActivityAd(DateTime dateTime) async {
    writeCalls += 1;
    if (throwOnWrite) throw StateError('write failed');
  }

  @override
  Future<void> setLastStartOfDayReward(DateTime dateTime) async {
    writeCalls += 1;
    if (throwOnWrite) throw StateError('write failed');
  }
}
