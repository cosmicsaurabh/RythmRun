import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
import 'package:rythmrun_frontend_flutter/core/services/session_invalidation_signal.dart';
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
        final repository = _FakeAuthRepository(
          events: events,
          currentUser: userA,
        );
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
        expect(repository.authCleanupPending, isTrue);
        expect(events, <String>[
          'activate:7',
          'mark-cleanup',
          'teardown',
          'activate:7',
        ]);
      },
    );

    test(
      'blocked forced loss cannot regain offline admission after restart',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          currentUser: userA,
          validationStatus: SessionValidationStatus.unavailable,
        );
        final firstNotifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(
            events: events,
            teardownResult: const UserScopeTeardownResult.blocked(
              requirement: UserScopeExitRequirement.unsavedWorkout,
              message: 'save failed',
            ),
          ),
          autoInitialize: false,
        );
        firstNotifier.onLoginSuccess(userA);

        final blocked = await firstNotifier.handleForcedAuthenticationLoss();
        expect(blocked.status, UserScopeTeardownStatus.blocked);
        expect(repository.authCleanupPending, isTrue);
        firstNotifier.dispose();

        final restartedNotifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(events: events),
        );
        addTearDown(restartedNotifier.dispose);
        await _flushAsyncWork();

        expect(restartedNotifier.state.state, SessionState.unauthenticated);
        expect(restartedNotifier.state.user, isNull);
        expect(repository.authCleanupPending, isFalse);
        expect(repository.clearCalls, 1);
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
          'mark-cleanup',
          'teardown',
          'clear',
        ]);
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
      },
    );

    test(
      'unverified credentials and network failure remain fail-closed',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          currentUser: userA,
          canStayOffline: false,
          validationStatus: SessionValidationStatus.unavailable,
        );
        final notifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(events: events),
        );
        addTearDown(notifier.dispose);

        await _flushAsyncWork();

        expect(notifier.state.state, SessionState.checking);
        expect(notifier.state.user, isNull);
        expect(notifier.isAuthenticated, isFalse);
        expect(repository.clearCalls, 0);
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

    test('refreshing verification state commits a newly verified email', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final teardown = _FakeUserScopeTeardown(events: events);
      final notifier = SessionNotifier(repository, teardown);
      addTearDown(notifier.dispose);

      await _flushAsyncWork();
      final admission = notifier.beginAuthenticationAttempt();
      expect(
        notifier.completeAuthenticationAttempt(
          userA.copyWith(emailVerified: false),
          admission!,
        ),
        isTrue,
      );
      expect(notifier.state.user?.emailVerified, isFalse);

      repository.serverUser = userA.copyWith(emailVerified: true);
      await notifier.refreshVerificationState();

      // Both the visible session and the cached copy are committed.
      expect(notifier.state.user?.emailVerified, isTrue);
      expect(repository.currentUser?.emailVerified, isTrue);
    });

    test('a failed verification refresh leaves session state untouched', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final teardown = _FakeUserScopeTeardown(events: events);
      final notifier = SessionNotifier(repository, teardown);
      addTearDown(notifier.dispose);

      await _flushAsyncWork();
      final admission = notifier.beginAuthenticationAttempt();
      notifier.completeAuthenticationAttempt(
        userA.copyWith(emailVerified: false),
        admission!,
      );

      repository.refreshCurrentUserError = StateError('offline');
      await notifier.refreshVerificationState();

      expect(notifier.state.user?.emailVerified, isFalse);
    });

    test('a verification refresh for another account is discarded', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final teardown = _FakeUserScopeTeardown(events: events);
      final notifier = SessionNotifier(repository, teardown);
      addTearDown(notifier.dispose);

      await _flushAsyncWork();
      final admission = notifier.beginAuthenticationAttempt();
      notifier.completeAuthenticationAttempt(
        userA.copyWith(emailVerified: false),
        admission!,
      );

      // A response owned by a different account must never be applied.
      repository.serverUser = userB.copyWith(emailVerified: true);
      await notifier.refreshVerificationState();

      expect(notifier.state.user?.emailVerified, isFalse);
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

    test(
      'refresh network failure preserves an eligible verified user offline',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          currentUser: userA,
          shouldRefresh: true,
          refreshError: const AuthSessionUnavailable(
            AuthSessionUnavailableReason.network,
          ),
        );
        final notifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(events: events),
        );
        addTearDown(notifier.dispose);

        await _flushAsyncWork();

        expect(notifier.state.state, SessionState.authenticatedOffline);
        expect(notifier.state.user, userA);
        expect(repository.clearCalls, 0);
        expect(events, <String>['activate:7']);
      },
    );

    test('rejected refresh performs forced teardown and clears auth', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(
        events: events,
        currentUser: userA,
        shouldRefresh: true,
        refreshError: const AuthSessionInvalid(
          AuthSessionInvalidReason.refreshRejected,
        ),
      );
      final notifier = SessionNotifier(
        repository,
        _FakeUserScopeTeardown(events: events),
      );
      addTearDown(notifier.dispose);

      await _flushAsyncWork();

      expect(notifier.state.state, SessionState.unauthenticated);
      expect(notifier.state.user, isNull);
      expect(events, <String>['mark-cleanup', 'teardown', 'clear']);
    });

    test(
      'background invalidation signal enters the same forced teardown',
      () async {
        final events = <String>[];
        final signal = SessionInvalidationSignal();
        addTearDown(signal.dispose);
        final repository = _FakeAuthRepository(
          events: events,
          currentUser: userA,
        );
        final notifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(events: events),
          sessionInvalidationSignal: signal,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(userA);

        signal.emitRefreshRejected(credentialRevision: 7);
        await _flushAsyncWork();

        expect(notifier.state.state, SessionState.unauthenticated);
        expect(notifier.state.user, isNull);
        expect(events, <String>[
          'activate:7',
          'mark-cleanup',
          'teardown',
          'clear',
        ]);
      },
    );

    test(
      'server rejection and network loss diverge from the same cached user',
      () async {
        // A backend 401/invalid session forces teardown to the guest root.
        final invalidEvents = <String>[];
        final invalidNotifier = SessionNotifier(
          _FakeAuthRepository(
            events: invalidEvents,
            currentUser: userA,
            validationStatus: SessionValidationStatus.invalid,
          ),
          _FakeUserScopeTeardown(events: invalidEvents),
        );
        addTearDown(invalidNotifier.dispose);
        await _flushAsyncWork();
        expect(invalidNotifier.state.state, SessionState.unauthenticated);
        expect(invalidNotifier.state.user, isNull);

        // Transient network loss keeps the same eligible user bounded-offline.
        final offlineEvents = <String>[];
        final offlineNotifier = SessionNotifier(
          _FakeAuthRepository(
            events: offlineEvents,
            currentUser: userA,
            validationStatus: SessionValidationStatus.unavailable,
          ),
          _FakeUserScopeTeardown(events: offlineEvents),
        );
        addTearDown(offlineNotifier.dispose);
        await _flushAsyncWork();
        expect(offlineNotifier.state.state, SessionState.authenticatedOffline);
        expect(offlineNotifier.state.user, userA);
      },
    );

    test(
      'the online operation guard mirrors full-online session state',
      () async {
        final events = <String>[];
        final repository = _FakeAuthRepository(
          events: events,
          validationStatus: SessionValidationStatus.unavailable,
        );
        final guard = OnlineOperationGuard();
        final notifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(events: events),
          onlineOperationGuard: guard,
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);

        notifier.onLoginSuccess(userA);
        expect(notifier.state.state, SessionState.authenticated);
        expect(guard.isOnline, isTrue);

        // Dropping to bounded offline mode revokes online-mutation admission.
        await notifier.validateSession();
        expect(notifier.state.state, SessionState.authenticatedOffline);
        expect(guard.isOnline, isFalse);

        await notifier.logout();
        expect(notifier.state.state, SessionState.unauthenticated);
        expect(guard.isOnline, isFalse);
      },
    );

    test('applyProfileUpdate merges only names for the same owner', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final notifier = SessionNotifier(
        repository,
        _FakeUserScopeTeardown(events: events),
        autoInitialize: false,
      );
      addTearDown(notifier.dispose);
      notifier.onLoginSuccess(
        userA.copyWith(
          profilePicturePath: 'avatars/7/current.jpg',
          profilePictureType: 'image/jpeg',
        ),
      );

      await notifier.applyProfileUpdate(
        ownerUserId: '7',
        updatedUser: const UserEntity(
          id: '7',
          firstName: 'Renamed',
          lastName: 'Runner',
          email: 'server-username@example.com',
        ),
      );

      final user = notifier.state.user!;
      expect(user.firstName, 'Renamed');
      expect(user.lastName, 'Runner');
      // Cached email and avatar fields stay owned by their own pipelines.
      expect(user.email, 'a@example.com');
      expect(user.profilePicturePath, 'avatars/7/current.jpg');
      expect(user.profilePictureType, 'image/jpeg');
      expect(repository.currentUser?.firstName, 'Renamed');
      expect(
        repository.currentUser?.profilePicturePath,
        'avatars/7/current.jpg',
      );
    });

    test(
      'a concurrent avatar and name commit preserve both owned fields',
      () async {
        final events = <String>[];
        final gate = Completer<void>();
        final repository = _FakeAuthRepository(
          events: events,
          gateFirstUserWrite: gate,
        );
        final notifier = SessionNotifier(
          repository,
          _FakeUserScopeTeardown(events: events),
          autoInitialize: false,
        );
        addTearDown(notifier.dispose);
        notifier.onLoginSuccess(
          userA.copyWith(
            profilePicturePath: 'avatars/7/old.jpg',
            profilePictureType: 'image/jpeg',
          ),
        );

        // The name commit blocks on its first persist.
        final nameFuture = notifier.applyProfileUpdate(
          ownerUserId: '7',
          updatedUser: const UserEntity(
            id: '7',
            firstName: 'Renamed',
            lastName: 'Runner',
            email: 'ignored@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // An avatar commit lands while the name persist is still in flight.
        await notifier.updateProfilePicture(
          ownerUserId: '7',
          path: 'avatars/7/new.jpg',
          type: 'image/png',
        );
        expect(notifier.state.user?.profilePicturePath, 'avatars/7/new.jpg');

        gate.complete();
        await nameFuture;

        // Neither commit clobbers the other's field.
        final user = notifier.state.user!;
        expect(user.firstName, 'Renamed');
        expect(user.profilePicturePath, 'avatars/7/new.jpg');
        expect(user.profilePictureType, 'image/png');
        expect(repository.currentUser?.firstName, 'Renamed');
        expect(repository.currentUser?.profilePicturePath, 'avatars/7/new.jpg');
      },
    );

    test('applyProfileUpdate discards a foreign or stale owner', () async {
      final events = <String>[];
      final repository = _FakeAuthRepository(events: events);
      final notifier = SessionNotifier(
        repository,
        _FakeUserScopeTeardown(events: events),
        autoInitialize: false,
      );
      addTearDown(notifier.dispose);
      notifier.onLoginSuccess(userA);

      // A server user that is not the requesting owner must never be applied.
      await notifier.applyProfileUpdate(
        ownerUserId: '7',
        updatedUser: const UserEntity(
          id: '8',
          firstName: 'Foreign',
          lastName: 'User',
          email: 'b@example.com',
        ),
      );
      // A stale owner (no longer the signed-in user) is discarded too.
      await notifier.applyProfileUpdate(
        ownerUserId: '8',
        updatedUser: const UserEntity(
          id: '8',
          firstName: 'Foreign',
          lastName: 'User',
          email: 'b@example.com',
        ),
      );

      expect(notifier.state.user, userA);
      expect(repository.currentUser, isNull);
    });

    test('password-change invalidation enters forced teardown', () async {
      final events = <String>[];
      final signal = SessionInvalidationSignal();
      addTearDown(signal.dispose);
      final repository = _FakeAuthRepository(
        events: events,
        currentUser: userA,
      );
      final notifier = SessionNotifier(
        repository,
        _FakeUserScopeTeardown(events: events),
        sessionInvalidationSignal: signal,
        autoInitialize: false,
      );
      addTearDown(notifier.dispose);
      notifier.onLoginSuccess(userA);

      signal.emitPasswordChanged(credentialRevision: 9);
      await _flushAsyncWork();

      expect(notifier.state.state, SessionState.unauthenticated);
      expect(notifier.state.user, isNull);
      expect(events, <String>[
        'activate:7',
        'mark-cleanup',
        'teardown',
        'clear',
      ]);
    });
  });
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeAuthRepository implements AuthRepository {
  /// Server-side user returned by [refreshCurrentUser]; set per test.
  UserEntity? serverUser;
  Object? refreshCurrentUserError;
  int resendCalls = 0;

  @override
  Future<UserEntity> refreshCurrentUser() async {
    final error = refreshCurrentUserError;
    if (error != null) throw error;
    final user = serverUser;
    if (user == null) {
      throw StateError('no server user configured for this test');
    }
    return user;
  }

  @override
  Future<void> resendVerificationEmail() async {
    resendCalls += 1;
  }

  final List<String> events;
  final bool failRemoteLogout;
  bool failLocalClear;
  final Completer<SessionValidationStatus>? validationCompleter;
  final Completer<UserEntity>? refreshCompleter;
  final Object? refreshError;
  final AuthenticationAttemptGate? mutationGate;
  final Completer<void>? gateFirstUserWrite;
  UserEntity? currentUser;
  bool shouldRefresh;
  final bool canStayOffline;
  bool authCleanupPending;
  SessionValidationStatus validationStatus;
  int clearCalls = 0;
  int userWrites = 0;

  _FakeAuthRepository({
    required this.events,
    this.failRemoteLogout = false,
    this.failLocalClear = false,
    this.validationCompleter,
    this.refreshCompleter,
    this.refreshError,
    this.mutationGate,
    this.gateFirstUserWrite,
    this.currentUser,
    this.shouldRefresh = false,
    this.canStayOffline = true,
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
  Future<bool> canStayLoggedInOffline() async => canStayOffline;

  @override
  Future<void> updateCurrentUser(UserEntity user) async {
    userWrites += 1;
    if (userWrites == 1 && gateFirstUserWrite != null) {
      await gateFirstUserWrite!.future;
    }
    currentUser = user;
  }

  @override
  Future<UserEntity> refreshToken() async {
    final lease = mutationGate?.tryAcquire();
    if (mutationGate != null && lease == null) {
      throw StateError('authentication mutation unavailable');
    }
    try {
      final error = refreshError;
      if (error != null) throw error;
      final user =
          refreshCompleter == null
              ? currentUser!
              : await refreshCompleter!.future;
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
