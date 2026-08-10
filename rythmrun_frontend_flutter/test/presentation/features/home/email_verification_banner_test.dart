import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/home/widgets/email_verification_banner.dart';

const _base = UserEntity(
  id: '7',
  firstName: 'Ada',
  lastName: 'Runner',
  email: 'runner@example.test',
);

Future<void> _pump(WidgetTester tester, UserEntity? user) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [currentUserProvider.overrideWithValue(user)],
      child: const MaterialApp(home: Scaffold(body: EmailVerificationBanner())),
    ),
  );
}

void main() {
  testWidgets('prompts a password account that has not confirmed its email', (
    tester,
  ) async {
    await _pump(tester, _base.copyWith(emailVerified: false));

    expect(find.textContaining('Confirm your email'), findsOneWidget);
    expect(find.text('Resend email'), findsOneWidget);
  });

  testWidgets('stays hidden once the email is confirmed', (tester) async {
    await _pump(tester, _base.copyWith(emailVerified: true));

    expect(find.textContaining('Confirm your email'), findsNothing);
  });

  testWidgets('never prompts a Google-only account', (tester) async {
    // Google already proved the address, and the account has no password
    // flow to fall back on, so the prompt would be wrong and unactionable.
    await _pump(
      tester,
      _base.copyWith(emailVerified: false, hasPassword: false),
    );

    expect(find.textContaining('Confirm your email'), findsNothing);
  });

  testWidgets('stays hidden when signed out', (tester) async {
    await _pump(tester, null);

    expect(find.textContaining('Confirm your email'), findsNothing);
  });

  testWidgets('can be dismissed for the session', (tester) async {
    await _pump(tester, _base.copyWith(emailVerified: false));
    expect(find.textContaining('Confirm your email'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(find.textContaining('Confirm your email'), findsNothing);
  });
}
