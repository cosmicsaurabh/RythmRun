import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';

void main() {
  test('denies server mutations until an online session is set', () {
    final guard = OnlineOperationGuard();

    expect(guard.isOnline, isFalse);
    expect(
      () => guard.requireOnline(),
      throwsA(
        isA<AuthSessionUnavailable>()
            .having(
              (error) => error.reason,
              'reason',
              AuthSessionUnavailableReason.offlineMode,
            )
            .having((error) => error.code, 'code', 'AUTH_OFFLINE_MODE')
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });

  test('permits mutations only while online', () {
    final guard = OnlineOperationGuard();

    guard.setOnline(true);
    expect(guard.isOnline, isTrue);
    expect(() => guard.requireOnline(), returnsNormally);

    guard.setOnline(false);
    expect(guard.isOnline, isFalse);
    expect(() => guard.requireOnline(), throwsA(isA<AuthSessionUnavailable>()));
  });
}
