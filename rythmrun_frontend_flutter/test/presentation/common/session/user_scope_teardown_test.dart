import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';

void main() {
  group('DefaultUserScopeTeardown', () {
    test(
      'voluntary logout requires a decision for an active workout',
      () async {
        var active = true;
        final events = <String>[];
        final coordinator = _coordinator(
          hasActive: () => active,
          events: events,
          finish: () async {
            active = false;
            return true;
          },
        );

        final result = await coordinator.teardown(
          reason: UserScopeExitReason.voluntaryLogout,
        );

        expect(result.status, UserScopeTeardownStatus.decisionRequired);
        expect(result.requirement, UserScopeExitRequirement.activeWorkout);
        expect(events, isEmpty);
      },
    );

    test(
      'forced auth loss finalizes before draining and invalidating',
      () async {
        var active = true;
        final events = <String>[];
        final coordinator = _coordinator(
          hasActive: () => active,
          events: events,
          finish: () async {
            events.add('finish');
            active = false;
            return true;
          },
        );

        final result = await coordinator.teardown(
          reason: UserScopeExitReason.forcedAuthenticationLoss,
        );

        expect(result.isCompleted, isTrue);
        expect(events, <String>['finish', 'drain', 'invalidate']);
      },
    );

    test(
      'failed finalization blocks auth cleanup and requests recovery',
      () async {
        var unsaved = false;
        final events = <String>[];
        final coordinator = _coordinator(
          hasActive: () => true,
          hasUnsaved: () => unsaved,
          events: events,
          finish: () async {
            events.add('finish');
            unsaved = true;
            return false;
          },
        );

        final result = await coordinator.teardown(
          reason: UserScopeExitReason.forcedAuthenticationLoss,
        );

        expect(result.status, UserScopeTeardownStatus.blocked);
        expect(result.requirement, UserScopeExitRequirement.unsavedWorkout);
        expect(result.message, contains('Retry or explicitly discard'));
        expect(events, <String>['finish']);
      },
    );

    test('retrying an unsaved workout must succeed before teardown', () async {
      var unsaved = true;
      final events = <String>[];
      final coordinator = _coordinator(
        hasActive: () => false,
        hasUnsaved: () => unsaved,
        events: events,
        retry: () async {
          events.add('retry');
          unsaved = false;
          return true;
        },
      );

      final result = await coordinator.teardown(
        reason: UserScopeExitReason.voluntaryLogout,
        decision: UserScopeExitDecision.retrySave,
      );

      expect(result.isCompleted, isTrue);
      expect(events, <String>['retry', 'drain', 'invalidate']);
    });

    test('explicit discard clears unsaved state before teardown', () async {
      var unsaved = true;
      final events = <String>[];
      final coordinator = _coordinator(
        hasActive: () => false,
        hasUnsaved: () => unsaved,
        events: events,
        discard: () async {
          events.add('discard');
          unsaved = false;
        },
      );

      final result = await coordinator.teardown(
        reason: UserScopeExitReason.voluntaryLogout,
        decision: UserScopeExitDecision.discardWorkout,
      );

      expect(result.isCompleted, isTrue);
      expect(events, <String>['discard', 'drain', 'invalidate']);
    });

    test(
      'tracking cleanup failure blocks exit until an explicit retry succeeds',
      () async {
        var active = true;
        var cleanupPending = false;
        final events = <String>[];
        final coordinator = _coordinator(
          hasActive: () => active,
          hasPendingCleanup: () => cleanupPending,
          events: events,
          finish: () async {
            events.add('finish');
            active = false;
            cleanupPending = true;
            return true;
          },
          retryCleanup: () async {
            events.add('retry-cleanup');
            cleanupPending = false;
            return true;
          },
        );

        final blocked = await coordinator.teardown(
          reason: UserScopeExitReason.forcedAuthenticationLoss,
        );

        expect(blocked.status, UserScopeTeardownStatus.blocked);
        expect(blocked.requirement, UserScopeExitRequirement.trackingCleanup);
        expect(events, <String>['finish']);

        final retried = await coordinator.teardown(
          reason: UserScopeExitReason.forcedAuthenticationLoss,
          decision: UserScopeExitDecision.retryTrackingCleanup,
        );

        expect(retried.isCompleted, isTrue);
        expect(events, <String>[
          'finish',
          'retry-cleanup',
          'drain',
          'invalidate',
        ]);
      },
    );

    test(
      'a workout appearing during quiescence still requires a voluntary choice',
      () async {
        var active = false;
        final events = <String>[];
        final coordinator = _coordinator(
          hasActive: () => active,
          events: events,
          quiesce: () async {
            events.add('quiesce');
            active = true;
            return true;
          },
          finish: () async {
            events.add('finish');
            return true;
          },
        );

        final result = await coordinator.teardown(
          reason: UserScopeExitReason.voluntaryLogout,
        );

        expect(result.status, UserScopeTeardownStatus.decisionRequired);
        expect(result.requirement, UserScopeExitRequirement.activeWorkout);
        expect(events, <String>['quiesce']);
      },
    );
  });
}

DefaultUserScopeTeardown _coordinator({
  required bool Function() hasActive,
  bool Function()? hasUnsaved,
  bool Function()? hasPendingCleanup,
  required List<String> events,
  Future<bool> Function()? finish,
  Future<bool> Function()? retry,
  Future<bool> Function()? retryCleanup,
  Future<bool> Function()? quiesce,
  Future<void> Function()? discard,
}) {
  return DefaultUserScopeTeardown(
    hasActiveWorkout: hasActive,
    hasUnsavedWorkout: hasUnsaved ?? () => false,
    hasPendingTrackingCleanup: hasPendingCleanup ?? () => false,
    quiesceTrackingOperations: quiesce ?? () async => true,
    finishWorkout: finish ?? () async => true,
    retryWorkoutSave: retry ?? () async => true,
    retryTrackingCleanup: retryCleanup ?? () async => true,
    discardWorkout: discard ?? () async {},
    suspendAndDrainWork: () async {
      events.add('drain');
    },
    invalidateUserState: () {
      events.add('invalidate');
    },
    activateWork: (_) {},
  );
}
