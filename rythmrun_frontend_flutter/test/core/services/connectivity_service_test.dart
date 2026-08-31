import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/connectivity_service.dart';

void main() {
  test(
    'late subscriber immediately receives the current platform state',
    () async {
      final changes = StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.test(
        checkConnectivity:
            () async => <ConnectivityResult>[ConnectivityResult.none],
        connectivityChanges: changes.stream,
      );
      addTearDown(() async {
        service.dispose();
        await changes.close();
      });

      await service.startMonitoring();

      expect(await service.statusStream.first, ConnectivityStatus.disconnected);
    },
  );

  testWidgets('monitor does not repeat the platform check on a timer', (
    tester,
  ) async {
    var checkCount = 0;
    final changes = StreamController<List<ConnectivityResult>>.broadcast();
    final service = ConnectivityService.test(
      checkConnectivity: () async {
        checkCount += 1;
        return <ConnectivityResult>[ConnectivityResult.wifi];
      },
      connectivityChanges: changes.stream,
    );
    addTearDown(() async {
      service.dispose();
      await changes.close();
    });

    await service.startMonitoring();
    await tester.pump(const Duration(minutes: 1));

    expect(checkCount, 1);
  });

  test('platform availability changes update connectivity status', () async {
    final changes = StreamController<List<ConnectivityResult>>.broadcast();
    final service = ConnectivityService.test(
      checkConnectivity:
          () async => <ConnectivityResult>[ConnectivityResult.none],
      connectivityChanges: changes.stream,
    );
    addTearDown(() async {
      service.dispose();
      await changes.close();
    });
    await service.startMonitoring();
    final statuses = <ConnectivityStatus>[];
    final subscription = service.statusStream.listen(statuses.add);
    addTearDown(subscription.cancel);
    await _pumpMicrotasks();

    changes.add(<ConnectivityResult>[ConnectivityResult.mobile]);
    await _pumpMicrotasks();

    expect(statuses, <ConnectivityStatus>[
      ConnectivityStatus.disconnected,
      ConnectivityStatus.connected,
    ]);
  });

  test('first change is not lost while current status is delivered', () async {
    final changes = StreamController<List<ConnectivityResult>>.broadcast(
      sync: true,
    );
    final service = ConnectivityService.test(
      checkConnectivity:
          () async => <ConnectivityResult>[ConnectivityResult.none],
      connectivityChanges: changes.stream,
    );
    addTearDown(() async {
      service.dispose();
      await changes.close();
    });
    await service.startMonitoring();

    final statuses = <ConnectivityStatus>[];
    final subscription = service.statusStream.listen((status) {
      statuses.add(status);
      if (statuses.length == 1) {
        changes.add(<ConnectivityResult>[ConnectivityResult.mobile]);
      }
    });
    addTearDown(subscription.cancel);
    await _pumpMicrotasks();

    expect(statuses, <ConnectivityStatus>[
      ConnectivityStatus.disconnected,
      ConnectivityStatus.connected,
    ]);
  });

  test('newer platform event wins over a stale initial check', () async {
    final initialCheck = Completer<List<ConnectivityResult>>();
    final changes = StreamController<List<ConnectivityResult>>.broadcast();
    final service = ConnectivityService.test(
      checkConnectivity: () => initialCheck.future,
      connectivityChanges: changes.stream,
    );
    addTearDown(() async {
      service.dispose();
      await changes.close();
    });

    final start = service.startMonitoring();
    changes.add(<ConnectivityResult>[ConnectivityResult.mobile]);
    await _pumpMicrotasks();
    initialCheck.complete(<ConnectivityResult>[ConnectivityResult.none]);
    await start;

    expect(service.currentStatus, ConnectivityStatus.connected);
  });

  test(
    'initial check from a stopped monitor cannot overwrite a restart',
    () async {
      final firstCheck = Completer<List<ConnectivityResult>>();
      final secondCheck = Completer<List<ConnectivityResult>>();
      var checkCount = 0;
      final changes = StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.test(
        checkConnectivity: () {
          checkCount += 1;
          return checkCount == 1 ? firstCheck.future : secondCheck.future;
        },
        connectivityChanges: changes.stream,
      );
      addTearDown(() async {
        service.dispose();
        await changes.close();
      });

      final firstStart = service.startMonitoring();
      service.stopMonitoring();
      final secondStart = service.startMonitoring();

      secondCheck.complete(<ConnectivityResult>[ConnectivityResult.wifi]);
      await secondStart;
      firstCheck.complete(<ConnectivityResult>[ConnectivityResult.none]);
      await firstStart;

      expect(checkCount, 2);
      expect(service.currentStatus, ConnectivityStatus.connected);
    },
  );
}

Future<void> _pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
