import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/workout_completion_ad_gate.dart';

void main() {
  group('WorkoutCompletionAdGate', () {
    test('requests one ad for each newly saved local workout ID', () async {
      final gate = WorkoutCompletionAdGate();
      var adRequests = 0;

      for (final workoutId in <int>[41, 42]) {
        final didRequestAd = await gate.showAfterDurableCompletion(
          result: LiveWorkoutFinalizationResult.saved(workoutId),
          hasPendingRecovery: false,
          isCurrentUserScope: () => true,
          showAd: () async {
            adRequests += 1;
          },
        );

        expect(didRequestAd, isTrue);
      }

      expect(adRequests, 2);
    });

    test('does not request a second ad for the same workout ID', () async {
      final gate = WorkoutCompletionAdGate();
      var adRequests = 0;

      Future<void> showAd() async {
        adRequests += 1;
      }

      final firstRequest = await gate.showAfterDurableCompletion(
        result: const LiveWorkoutFinalizationResult.saved(41),
        hasPendingRecovery: false,
        isCurrentUserScope: () => true,
        showAd: showAd,
      );
      final duplicateRequest = await gate.showAfterDurableCompletion(
        result: const LiveWorkoutFinalizationResult.saved(41),
        hasPendingRecovery: false,
        isCurrentUserScope: () => true,
        showAd: showAd,
      );

      expect(firstRequest, isTrue);
      expect(duplicateRequest, isFalse);
      expect(adRequests, 1);
    });

    test(
      'contains an optional ad failure and still claims the workout',
      () async {
        final gate = WorkoutCompletionAdGate();
        var adRequests = 0;

        Future<void> failingAd() async {
          adRequests += 1;
          throw StateError('simulated SDK failure');
        }

        final firstRequest = await gate.showAfterDurableCompletion(
          result: const LiveWorkoutFinalizationResult.saved(41),
          hasPendingRecovery: false,
          isCurrentUserScope: () => true,
          showAd: failingAd,
        );
        final duplicateRequest = await gate.showAfterDurableCompletion(
          result: const LiveWorkoutFinalizationResult.saved(41),
          hasPendingRecovery: false,
          isCurrentUserScope: () => true,
          showAd: failingAd,
        );

        expect(firstRequest, isTrue);
        expect(duplicateRequest, isFalse);
        expect(adRequests, 1);
      },
    );

    test(
      'does not request an ad before durable recovery is complete',
      () async {
        final gate = WorkoutCompletionAdGate();
        var adRequests = 0;

        Future<void> showAd() async {
          adRequests += 1;
        }

        final ineligibleResults = <LiveWorkoutFinalizationResult>[
          const LiveWorkoutFinalizationResult(
            LiveWorkoutFinalizationStatus.savePending,
          ),
          const LiveWorkoutFinalizationResult(
            LiveWorkoutFinalizationStatus.failed,
          ),
          const LiveWorkoutFinalizationResult(
            LiveWorkoutFinalizationStatus.noActiveWorkout,
          ),
        ];

        for (final result in ineligibleResults) {
          final didRequestAd = await gate.showAfterDurableCompletion(
            result: result,
            hasPendingRecovery: false,
            isCurrentUserScope: () => true,
            showAd: showAd,
          );

          expect(didRequestAd, isFalse);
        }

        final didRequestDuringRecovery = await gate.showAfterDurableCompletion(
          result: const LiveWorkoutFinalizationResult.saved(41),
          hasPendingRecovery: true,
          isCurrentUserScope: () => true,
          showAd: showAd,
        );
        final didRequestAfterScopeChange = await gate
            .showAfterDurableCompletion(
              result: const LiveWorkoutFinalizationResult.saved(42),
              hasPendingRecovery: false,
              isCurrentUserScope: () => false,
              showAd: showAd,
            );

        expect(didRequestDuringRecovery, isFalse);
        expect(didRequestAfterScopeChange, isFalse);
        expect(adRequests, 0);
      },
    );
  });
}
