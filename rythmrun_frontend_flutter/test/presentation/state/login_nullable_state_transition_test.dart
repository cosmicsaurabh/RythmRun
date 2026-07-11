import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/providers/login_notifier.dart';

void main() {
  test('successful login retry clears the previous error', () async {
    final repository = _FakeLoginRepository(failuresRemaining: 1);
    final authenticatedUsers = <UserEntity>[];
    final notifier = LoginNotifier(
      LoginUserUsecase(repository),
      beginAuthentication: () => 0,
      completeAuthentication: (user, _) {
        authenticatedUsers.add(user);
        return true;
      },
    );
    addTearDown(notifier.dispose);
    notifier.updateEmail('runner@example.com');
    notifier.updatePassword('password');

    await notifier.loginUser();
    expect(notifier.state.errorMessage, isNotNull);

    await notifier.loginUser();
    expect(notifier.state.errorMessage, isNull);
    expect(notifier.state.isSuccess, isTrue);
    expect(authenticatedUsers, hasLength(1));
  });

  test(
    'authenticated session blocks login before the repository call',
    () async {
      final repository = _FakeLoginRepository(failuresRemaining: 0);
      final notifier = LoginNotifier(
        LoginUserUsecase(repository),
        beginAuthentication: () => null,
        completeAuthentication:
            (_, _) => fail('login success must not be reported'),
      );
      addTearDown(notifier.dispose);

      await notifier.loginUser();

      expect(repository.loginCalls, 0);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, contains('Sign out'));
    },
  );

  test('duplicate submissions cannot start concurrent logins', () async {
    final repository = _FakeLoginRepository(failuresRemaining: 0);
    final loginCompleter = Completer<UserEntity>();
    repository.loginCompleter = loginCompleter;
    final notifier = LoginNotifier(
      LoginUserUsecase(repository),
      beginAuthentication: () => 0,
      completeAuthentication: (_, _) => true,
    );
    addTearDown(notifier.dispose);

    final firstLogin = notifier.loginUser();
    expect(notifier.state.isLoading, isTrue);

    await notifier.loginUser();
    expect(repository.loginCalls, 1);

    loginCompleter.complete(_FakeLoginRepository.user);
    await firstLogin;
    expect(notifier.state.isSuccess, isTrue);
  });
}

class _FakeLoginRepository implements AuthRepository {
  _FakeLoginRepository({required this.failuresRemaining});

  int failuresRemaining;
  int loginCalls = 0;
  Completer<UserEntity>? loginCompleter;

  static const user = UserEntity(
    id: '7',
    firstName: 'A',
    lastName: 'Runner',
    email: 'runner@example.com',
  );

  @override
  Future<UserEntity> login(LoginRequestEntity request) async {
    loginCalls += 1;
    final pendingLogin = loginCompleter;
    if (pendingLogin != null) {
      return pendingLogin.future;
    }
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('simulated login failure');
    }
    return user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
