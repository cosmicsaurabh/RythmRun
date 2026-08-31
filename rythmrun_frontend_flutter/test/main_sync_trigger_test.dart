import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/connectivity_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/main.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';

void main() {
  testWidgets(
    'disconnected to slow requests one sync without a slow to connected duplicate',
    (tester) async {
      final session = StateProvider<SessionData>(
        (ref) => const SessionData(state: SessionState.authenticated),
      );
      final connectivity = StateProvider<AsyncValue<ConnectivityStatus>>(
        (ref) => const AsyncData(ConnectivityStatus.disconnected),
      );
      final liveTracking = StateProvider<LiveTrackingState>(
        (ref) => const LiveTrackingState(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var syncRequests = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppSyncTriggerObserver(
            sessionListenable: session,
            connectivityListenable: connectivity,
            liveTrackingListenable: liveTracking,
            syncRequest: () async {
              syncRequests += 1;
            },
            child: const SizedBox(),
          ),
        ),
      );

      container.read(connectivity.notifier).state = const AsyncData(
        ConnectivityStatus.slow,
      );
      await tester.pump();
      expect(syncRequests, 1);

      container.read(connectivity.notifier).state = const AsyncData(
        ConnectivityStatus.connected,
      );
      await tester.pump();
      expect(syncRequests, 1);
    },
  );

  testWidgets('resume defers active and paused workouts but syncs when idle', (
    tester,
  ) async {
    final session = StateProvider<SessionData>(
      (ref) => const SessionData(state: SessionState.authenticated),
    );
    final connectivity = StateProvider<AsyncValue<ConnectivityStatus>>(
      (ref) => const AsyncData(ConnectivityStatus.disconnected),
    );
    final liveTracking = StateProvider<LiveTrackingState>(
      (ref) =>
          LiveTrackingState(currentSession: _workout(WorkoutStatus.active)),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var syncRequests = 0;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppSyncTriggerObserver(
          sessionListenable: session,
          connectivityListenable: connectivity,
          liveTrackingListenable: liveTracking,
          syncRequest: () async {
            syncRequests += 1;
          },
          child: const SizedBox(),
        ),
      ),
    );

    await _resumeApp(tester);
    expect(syncRequests, 0);

    container.read(liveTracking.notifier).state = LiveTrackingState(
      currentSession: _workout(WorkoutStatus.paused),
    );
    await tester.pump();
    await _resumeApp(tester);
    expect(syncRequests, 0);

    container.read(liveTracking.notifier).state = const LiveTrackingState();
    await tester.pump();
    await _resumeApp(tester);
    expect(syncRequests, 1);
  });
}

Future<void> _resumeApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

WorkoutSessionEntity _workout(WorkoutStatus status) {
  return WorkoutSessionEntity(
    clientSyncId: 'local-workout',
    type: WorkoutType.running,
    status: status,
    userId: 7,
  );
}
