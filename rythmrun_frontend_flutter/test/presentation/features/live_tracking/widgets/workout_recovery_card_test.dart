import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/widgets/workout_recovery_card.dart';

void main() {
  Widget subject({
    required bool savePending,
    required bool isBusy,
    required VoidCallback onRetry,
    required VoidCallback onDiscard,
    String? errorMessage,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: WorkoutRecoveryCard(
          savePending: savePending,
          isBusy: isBusy,
          errorMessage: errorMessage,
          onRetry: onRetry,
          onDiscard: onDiscard,
        ),
      ),
    );
  }

  testWidgets('failed save stays actionable with retry and discard', (
    tester,
  ) async {
    var retries = 0;
    var discards = 0;
    await tester.pumpWidget(
      subject(
        savePending: true,
        isBusy: false,
        errorMessage: 'Workout is not saved yet.',
        onRetry: () => retries += 1,
        onDiscard: () => discards += 1,
      ),
    );

    expect(find.text('Workout not saved'), findsOneWidget);
    expect(find.text('Workout is not saved yet.'), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
    expect(find.text('Discard unsaved workout'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-workout-recovery')));
    await tester.tap(find.byKey(const ValueKey('discard-unsaved-workout')));

    expect(retries, 1);
    expect(discards, 1);
  });

  testWidgets('cleanup recovery never offers workout discard', (tester) async {
    await tester.pumpWidget(
      subject(
        savePending: false,
        isBusy: false,
        onRetry: () {},
        onDiscard: () {},
      ),
    );

    expect(find.text('Cleanup still pending'), findsOneWidget);
    expect(find.text('Retry cleanup'), findsOneWidget);
    expect(find.byKey(const ValueKey('discard-unsaved-workout')), findsNothing);
  });
}
