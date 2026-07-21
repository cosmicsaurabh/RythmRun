import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/request_password_reset_usecase.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/forgot_password/providers/forgot_password_notifier.dart';

class _FakeAuthRepository implements AuthRepository {
  final List<String> calls = <String>[];
  Object? error;

  @override
  Future<void> requestPasswordReset(String email) async {
    calls.add(email);
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ForgotPasswordNotifier _build(_FakeAuthRepository repo) =>
    ForgotPasswordNotifier(RequestPasswordResetUsecase(repo));

void main() {
  test('submits a canonicalized email and reports generic success', () async {
    final repo = _FakeAuthRepository();
    final notifier = _build(repo);
    addTearDown(notifier.dispose);

    notifier.updateEmail('  Runner@Example.COM ');
    await notifier.submit();

    expect(repo.calls, <String>['runner@example.com']);
    expect(notifier.state.isSent, isTrue);
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.errorMessage, isNull);
  });

  test('rejects an invalid email without calling the backend', () async {
    final repo = _FakeAuthRepository();
    final notifier = _build(repo);
    addTearDown(notifier.dispose);

    notifier.updateEmail('not-an-email');
    await notifier.submit();

    expect(repo.calls, isEmpty);
    expect(notifier.state.isSent, isFalse);
    expect(notifier.state.errorMessage, isNotNull);
  });

  test('surfaces a network/server error without marking sent', () async {
    final repo = _FakeAuthRepository()..error = Exception('network down');
    final notifier = _build(repo);
    addTearDown(notifier.dispose);

    notifier.updateEmail('runner@example.com');
    await notifier.submit();

    expect(notifier.state.isSent, isFalse);
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.errorMessage, isNotNull);
  });

  test('editing the email clears a previous error', () async {
    final repo = _FakeAuthRepository();
    final notifier = _build(repo);
    addTearDown(notifier.dispose);

    notifier.updateEmail('bad');
    await notifier.submit();
    expect(notifier.state.errorMessage, isNotNull);

    notifier.updateEmail('runner@example.com');
    expect(notifier.state.errorMessage, isNull);
  });
}
