import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';

void main() {
  const userA = UserEntity(
    id: '7',
    firstName: 'A',
    lastName: 'Runner',
    email: 'a@example.com',
  );
  const userB = UserEntity(
    id: '8',
    firstName: 'B',
    lastName: 'Runner',
    email: 'b@example.com',
  );

  group('SessionData nullable contract', () {
    test('omitted values retain and explicit null clears user and error', () {
      const original = SessionData(
        state: SessionState.authenticated,
        user: userA,
        errorMessage: 'old error',
        pendingExitReason: UserScopeExitReason.voluntaryLogout,
      );

      expect(original.copyWith().user, userA);
      expect(original.copyWith().errorMessage, 'old error');
      expect(
        original.copyWith().pendingExitReason,
        UserScopeExitReason.voluntaryLogout,
      );

      final cleared = original.copyWith(
        user: null,
        errorMessage: null,
        pendingExitReason: null,
      );
      expect(cleared.user, isNull);
      expect(cleared.errorMessage, isNull);
      expect(cleared.pendingExitReason, isNull);
    });
  });

  group('SessionNotifier user-scope transitions', () {
    test(
      'idle logout tears down before clearing auth even if remote fails',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          failRemoteLogout: true,
        );
        final teardown = _FakeUserScopeTeardown(events: events);
        final notifier = SessionNotifier(
          repository,
          teardown,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        final result = await notifier.logout();

        expect(result.isCompleted, isTrue);
        expect(events, <String>[
          'activate:7',
          'teardown',
          'mark-cleanup',
          'remote',
          'clear',
        ]);
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
        expect(notifier.state.errorMessage, isNull);
      },
    );

    test('active workout blocks logout until a decision is supplied', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final teardown = _FakeUserScopeTeardown(
        events: events,
        requirement: UserScopeExitRequirement.activeWorkout,
      );
      final notifier = SessionNotifier(
        repository,
        teardown,
        autoInitialize: false,
      );
      addTearDown(notifier.dispose);
      notifier.onLoginSuccess(userA);

      final result = await notifier.logout();

      expect(result.status, UserScopeTeardownStatus.decisionRequired);
      expect(notifier.state.user, userA);
      expect(
        notifier.state.exitRequirement,
        UserScopeExitRequirement.activeWorkout,
      );
      expect(events, <String>['activate:7']);
    });

    test(
      'a teardown preflight failure becomes a recoverable account action',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(events: events);
        final teardown = _FakeUserScopeTeardown(
          events: events,
          throwRequirement: true,
        );
        final notifier = SessionNotifier(
          repository,
          teardown,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        final result = await notifier.logout();

        expect(result.status, UserScopeTeardownStatus.blocked);
        expect(result.requirement, UserScopeExitRequirement.accountCleanup);
        expect(
          notifier.state.exitRequirement,
          UserScopeExitRequirement.accountCleanup,
        );
        expect(
          notifier.state.pendingExitReason,
          UserScopeExitReason.voluntaryLogout,
        );
        expect(events, <String>['activate:7']);
      },
    );

    test(
      'forced auth loss remains blocked when local finalization fails',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(events: events);
        final teardown = _FakeUserScopeTeardown(
          events: events,
          teardownResult: const UserScopeTeardownResult.blocked(
            requirement: UserScopeExitRequirement.unsavedWorkout,
            message: 'save failed',
          ),
        );
        final notifier = SessionNotifier(
          repository,
          teardown,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        final result = await notifier.handleForcedAuthenticationLoss();

        expect(result.status, UserScopeTeardownStatus.blocked);
        expect(notifier.state.user, userA);
        expect(notifier.state.state, SessionState.authenticated);
        expect(
          notifier.state.pendingExitReason,
          UserScopeExitReason.forcedAuthenticationLoss,
        );
        expect(
          notifier.state.exitRequirement,
          UserScopeExitRequirement.unsavedWorkout,
        );
        expect(repository.clearCalls, 0);
        expect(events, <String>['activate:7', 'teardown', 'activate:7']);
      },
    );

    test(
      'network-unavailable validation keeps the same user offline',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          validationStatus: SessionValidationStatus.unavailable,
        );
        final teardown = _FakeUserScopeTeardown(events: events);
        final notifier = SessionNotifier(
          repository,
          teardown,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        await notifier.validateSession();

        expect(notifier.state.state, SessionState.authenticatedOffline);
        expect(notifier.state.user, userA);
        expect(repository.clearCalls, 0);
        expect(events, <String>['activate:7', 'activate:7']);
      },
    );

    test(
      'invalid validation uses forced teardown before clearing auth',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          validationStatus: SessionValidationStatus.invalid,
        );
        final teardown = _FakeUserScopeTeardown(events: events);
        final notifier = SessionNotifier(
          repository,
          teardown,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        await notifier.validateSession();

        expect(events, <String>[
          'activate:7',
          'teardown',
          'mark-cleanup',
          'clear',
        ]);
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
      },
    );

    test('A logout then B login activates a clean B scope', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final teardown = _FakeUserScopeTeardown(events: events);
      final notifier = SessionNotifier(
        repository,
        teardown,
        autoInitialize: false,
      );
      addTearDown(notifier.dispose);

      notifier.onLoginSuccess(userA);
      await notifier.logout();
      notifier.onLoginSuccess(userB);

      expect(notifier.state.user, userB);
      expect(notifier.state.state, SessionState.authenticated);
      expect(events, <String>[
        'activate:7',
        'teardown',
        'mark-cleanup',
        'remote',
        'clear',
        'activate:8',
      ]);
    });

    test(
      'local credential-clear failure blocks B until cleanup retry succeeds',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          failLocalClear: true,
        );
        final teardown = _FakeUserScopeTeardown(events: events);
        final notifier = SessionNotifier(
          repository,
          teardown,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        final failedExit = await notifier.logout();

        expect(failedExit.status, UserScopeTeardownStatus.blocked);
        expect(
          failedExit.requirement,
          UserScopeExitRequirement.localCredentialCleanup,
        );
        expect(notifier.state.state, SessionState.checking);
        expect(notifier.state.user, userA);
        expect(notifier.blocksNewAuthentication, isTrue);
        expect(
          notifier.state.pendingExitReason,
          UserScopeExitReason.voluntaryLogout,
        );

        notifier.onLoginSuccess(userB);
        expect(notifier.state.user, userA);

        repository.failLocalClear = false;
        final retriedExit = await notifier.resolvePendingExit(
          UserScopeExitDecision.retryCredentialCleanup,
        );

        expect(retriedExit.isCompleted, isTrue);
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
        expect(notifier.blocksNewAuthentication, isFalse);
        expect(events, <String>[
          'activate:7',
          'teardown',
          'mark-cleanup',
          'remote',
          'clear',
          'teardown',
          'mark-cleanup',
          'remote',
          'clear',
        ]);
      },
    );

    test('a delayed validation cannot restore A after logout', () async {
      final events = <String>[];
      final validationCompleter = Completer<SessionValidationStatus>();
      final repository = _FakeAuthRepository(
        events: events,
        validationCompleter: validationCompleter,
      );
      final teardown = _FakeUserScopeTeardown(events: events);
      final notifier = SessionNotifier(
        repository,
        teardown,
        autoInitialize: false,
      );
      addTearDown(notifier.dispose);
      notifier.onLoginSuccess(userA);

      final delayedValidation = notifier.validateSession();
      await Future<void>.delayed(Duration.zero);
      final logoutResult = await notifier.logout();
      validationCompleter.complete(SessionValidationStatus.valid);
      await delayedValidation;

      expect(logoutResult.isCompleted, isTrue);
      expect(notifier.state.state, SessionState.unauthenticated);
      expect(notifier.state.user, isNull);
      expect(events, <String>[
        'activate:7',
        'teardown',
        'mark-cleanup',
        'remote',
        'clear',
      ]);
    });

    test('startup finishes a persisted cleanup before restoring A', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(
        events: events,
        currentUser: userA,
        authCleanupPending: true,
      );
      final teardown = _FakeUserScopeTeardown(events: events);
      final notifier = SessionNotifier(repository, teardown);
      addTearDown(notifier.dispose);

      await _flushAsyncWork();

      expect(notifier.state.state, SessionState.unauthenticated);
      expect(notifier.state.user, isNull);
      expect(repository.currentUser, isNull);
      expect(repository.authCleanupPending, isFalse);
      expect(events, <String>['clear']);
    });

    test(
      'authentication admission opens only after startup is unauthenticated',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(events: events);
        final teardown = _FakeUserScopeTeardown(events: events);
        final notifier = SessionNotifier(repository, teardown);
        addTearDown(notifier.dispose);

        expect(notifier.blocksNewAuthentication, isTrue);
        expect(notifier.beginAuthenticationAttempt(), isNull);

        await _flushAsyncWork();

        expect(notifier.state.state, SessionState.unauthenticated);
        final admission = notifier.beginAuthenticationAttempt();
        expect(admission, isNotNull);

        await notifier.logout();
        expect(
          notifier.completeAuthenticationAttempt(userB, admission!),
          isFalse,
        );
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
      },
    );

    test(
      'logout drains a delayed refresh before marking and clearing credentials',
      () async {
        final events = <String>[];
        final mutationGate = AuthenticationAttemptGate();
        final refreshCompleter = Completer<UserEntity>();
        final repository = _FakeAuthRepository(
          events: events,
          currentUser: userA,
          shouldRefresh: true,
          refreshCompleter: refreshCompleter,
          mutationGate: mutationGate,
        );
        final teardown = _FakeUserScopeTeardown(events: events);
        final notifier = SessionNotifier(
          repository,
          teardown,
          authenticationAttemptGate: mutationGate,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        final delayedRefresh = notifier.refreshSession();
        await _flushAsyncWork();
        expect(mutationGate.isActive, isTrue);
        expect(notifier.state.state, SessionState.refreshing);
        expect(notifier.state.user, userA);
        expect(notifier.blocksNewAuthentication, isTrue);

        notifier.onLoginSuccess(userB);
        expect(notifier.state.user, userA);

        final pendingLogout = notifier.logout();
        await _flushAsyncWork();
        expect(mutationGate.isSuspended, isTrue);

        refreshCompleter.complete(userA);
        await delayedRefresh;
        final logoutResult = await pendingLogout;

        expect(logoutResult.isCompleted, isTrue);
        expect(repository.currentUser, isNull);
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
        expect(mutationGate.isSuspended, isFalse);
        expect(events, <String>[
          'activate:7',
          'teardown',
          'refresh-save:7',
          'mark-cleanup',
          'remote',
          'clear',
        ]);
      },
    );
  });
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeAuthRepository implements AuthRepository {
  final List<String> events;
  final bool failRemoteLogout;
  bool failLocalClear;
  final Completer<SessionValidationStatus>? validationCompleter;
  final Completer<UserEntity>? refreshCompleter;
  final AuthenticationAttemptGate? mutationGate;
  UserEntity? currentUser;
  bool shouldRefresh;
  bool authCleanupPending;
  SessionValidationStatus validationStatus;
  int clearCalls = 0;

  _FakeAuthRepository({
    required this.events,
    this.failRemoteLogout = false,
    this.failLocalClear = false,
    this.validationCompleter,
    this.refreshCompleter,
    this.mutationGate,
    this.currentUser,
    this.shouldRefresh = false,
    this.authCleanupPending = false,
    this.validationStatus = SessionValidationStatus.valid,
  });

  @override
  Future<void> logout() async {
    events.add('remote');
    if (failRemoteLogout) throw StateError('simulated remote failure');
  }

  @override
  Future<void> clearAuthData() async {
    clearCalls += 1;
    events.add('clear');
    if (failLocalClear) throw StateError('simulated local clear failure');
    currentUser = null;
    authCleanupPending = false;
  }

  @override
  Future<void> markAuthCleanupPending() async {
    events.add('mark-cleanup');
    authCleanupPending = true;
  }

  @override
  Future<bool> hasPendingAuthCleanup() async => authCleanupPending;

  @override
  Future<UserEntity?> getCurrentUser() async => currentUser;

  @override
  Future<bool> needsTokenRefresh() async => shouldRefresh;

  @override
  Future<bool> canStayLoggedInOffline() async => true;

  @override
  Future<void> printStoredData() async {}

  @override
  Future<UserEntity> refreshToken() async {
    final lease = mutationGate?.tryAcquire();
    if (mutationGate != null && lease == null) {
      throw StateError('authentication mutation unavailable');
    }
    try {
      final user = await refreshCompleter!.future;
      currentUser = user;
      events.add('refresh-save:${user.id}');
      return user;
    } finally {
      lease?.release();
    }
  }

  @override
  Future<SessionValidationStatus> validateSession() async {
    return validationCompleter?.future ?? validationStatus;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserScopeTeardown implements UserScopeTeardown {
  final List<String> events;
  final UserScopeExitRequirement requirement;
  final UserScopeTeardownResult teardownResult;
  final bool throwRequirement;

  _FakeUserScopeTeardown({
    required this.events,
    this.requirement = UserScopeExitRequirement.none,
    this.teardownResult = const UserScopeTeardownResult.completed(),
    this.throwRequirement = false,
  });

  @override
  void activateUserScope(String userId) {
    events.add('activate:$userId');
  }

  @override
  UserScopeExitRequirement requirementFor(UserScopeExitReason reason) {
    if (throwRequirement) throw StateError('simulated preflight failure');
    return requirement;
  }

  @override
  Future<UserScopeTeardownResult> teardown({
    required UserScopeExitReason reason,
    UserScopeExitDecision? decision,
  }) async {
    events.add('teardown');
    return teardownResult;
  }
}
