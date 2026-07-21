import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/core/services/google_identity_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_with_google_usecase.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/providers/login_notifier.dart';

void main() {
  test('successful login retry clears the previous error', () async {
    final repository = _FakeLoginRepository(failuresRemaining: 1);
    final authenticatedUsers = <UserEntity>[];
    final notifier = LoginNotifier(
      LoginUserUsecase(repository),
      loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
      googleIdentityService: _FakeGoogleIdentityService(),
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
        loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
        googleIdentityService: _FakeGoogleIdentityService(),
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
      loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
      googleIdentityService: _FakeGoogleIdentityService(),
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

  test(
    'canceling Google account selection is not reported as an error',
    () async {
      final repository = _FakeLoginRepository(
        failuresRemaining: 0,
        googleCanceled: true,
      );
      final notifier = LoginNotifier(
        LoginUserUsecase(repository),
        loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
        googleIdentityService: _FakeGoogleIdentityService(),
        beginAuthentication: () => 0,
        completeAuthentication:
            (_, _) => fail('a canceled login must not authenticate a session'),
      );
      addTearDown(notifier.dispose);

      await notifier.loginWithGoogle();

      expect(repository.googleLoginCalls, 1);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isSuccess, isFalse);
      expect(notifier.state.method, isNull);
    },
  );

  test('successful Google login completes normal session admission', () async {
    final repository = _FakeLoginRepository(failuresRemaining: 0);
    final google = _FakeGoogleIdentityService();
    final authenticatedUsers = <UserEntity>[];
    final notifier = LoginNotifier(
      LoginUserUsecase(repository),
      loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
      googleIdentityService: google,
      beginAuthentication: () => 4,
      completeAuthentication: (user, admission) {
        expect(admission, 4);
        authenticatedUsers.add(user);
        return true;
      },
    );
    addTearDown(notifier.dispose);

    await notifier.loginWithGoogle();

    expect(repository.googleLoginCalls, 1);
    expect(authenticatedUsers, <UserEntity>[_FakeLoginRepository.user]);
    expect(notifier.state.isSuccess, isTrue);
    expect(google.signOutCalls, 0);
  });

  test(
    'Google authentication failure is surfaced without session admission',
    () async {
      final repository = _FakeLoginRepository(
        failuresRemaining: 0,
        googleFailure: StateError('exchange failed'),
      );
      final notifier = LoginNotifier(
        LoginUserUsecase(repository),
        loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
        googleIdentityService: _FakeGoogleIdentityService(),
        beginAuthentication: () => 0,
        completeAuthentication:
            (_, _) => fail('failed exchange must not authenticate a session'),
      );
      addTearDown(notifier.dispose);

      await notifier.loginWithGoogle();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, contains('exchange failed'));
    },
  );

  test(
    'duplicate Google taps cannot start concurrent repository flows',
    () async {
      final repository = _FakeLoginRepository(failuresRemaining: 0);
      final pendingUser = Completer<UserEntity?>();
      repository.googleLoginCompleter = pendingUser;
      final notifier = LoginNotifier(
        LoginUserUsecase(repository),
        loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
        googleIdentityService: _FakeGoogleIdentityService(),
        beginAuthentication: () => 0,
        completeAuthentication: (_, _) => true,
      );
      addTearDown(notifier.dispose);

      final firstLogin = notifier.loginWithGoogle();
      await Future<void>.delayed(Duration.zero);
      await notifier.loginWithGoogle();

      expect(repository.googleLoginCalls, 1);
      pendingUser.complete(null);
      await firstLogin;
    },
  );

  test('stale Google admission signs out the native account', () async {
    final repository = _FakeLoginRepository(failuresRemaining: 0);
    final google = _FakeGoogleIdentityService();
    final notifier = LoginNotifier(
      LoginUserUsecase(repository),
      loginWithGoogleUsecase: LoginWithGoogleUsecase(repository),
      googleIdentityService: google,
      beginAuthentication: () => 2,
      completeAuthentication: (_, _) => false,
    );
    addTearDown(notifier.dispose);

    await notifier.loginWithGoogle();

    expect(google.signOutCalls, 1);
    expect(notifier.state.errorMessage, contains('account context changed'));
  });
}

class _FakeLoginRepository implements AuthRepository {
  @override
  Future<UserEntity> refreshCurrentUser() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

  _FakeLoginRepository({
    required this.failuresRemaining,
    this.googleFailure,
    this.googleCanceled = false,
  });

  int failuresRemaining;
  int loginCalls = 0;
  Completer<UserEntity>? loginCompleter;
  final Object? googleFailure;
  final bool googleCanceled;
  int googleLoginCalls = 0;
  Completer<UserEntity?>? googleLoginCompleter;

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
  Future<UserEntity?> loginWithGoogle() async {
    googleLoginCalls += 1;
    final pendingLogin = googleLoginCompleter;
    if (pendingLogin != null) return pendingLogin.future;
    final failure = googleFailure;
    if (failure != null) throw failure;
    if (googleCanceled) return null;
    return user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleIdentityService implements GoogleIdentityService {
  int signOutCalls = 0;

  @override
  Future<String?> authenticate() async => 'unused-google-token';

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
}
