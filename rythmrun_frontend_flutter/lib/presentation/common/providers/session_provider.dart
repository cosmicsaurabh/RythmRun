import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/auth_failures.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/entities/user_entity.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/authentication_attempt_gate.dart';
import '../../../core/services/online_operation_guard.dart';
import '../../../core/services/session_invalidation_signal.dart';
import '../session/user_scope_teardown.dart';
import 'user_scope_teardown_provider.dart';

const Object _unsetSessionValue = Object();

enum SessionState {
  initial,
  checking,
  authenticated, // Full access - online and offline
  authenticatedOffline, // Limited access - offline features only
  unauthenticated,
  refreshing,
}

class SessionData {
  final SessionState state;
  final UserEntity? user;
  final String? errorMessage;
  final UserScopeExitRequirement exitRequirement;
  final UserScopeExitReason? pendingExitReason;

  const SessionData({
    required this.state,
    this.user,
    this.errorMessage,
    this.exitRequirement = UserScopeExitRequirement.none,
    this.pendingExitReason,
  });

  SessionData copyWith({
    SessionState? state,
    Object? user = _unsetSessionValue,
    Object? errorMessage = _unsetSessionValue,
    UserScopeExitRequirement? exitRequirement,
    Object? pendingExitReason = _unsetSessionValue,
  }) {
    return SessionData(
      state: state ?? this.state,
      user:
          identical(user, _unsetSessionValue) ? this.user : user as UserEntity?,
      errorMessage:
          identical(errorMessage, _unsetSessionValue)
              ? this.errorMessage
              : errorMessage as String?,
      exitRequirement: exitRequirement ?? this.exitRequirement,
      pendingExitReason:
          identical(pendingExitReason, _unsetSessionValue)
              ? this.pendingExitReason
              : pendingExitReason as UserScopeExitReason?,
    );
  }
}

class SessionNotifier extends StateNotifier<SessionData> {
  final AuthRepository _authRepository;
  final UserScopeTeardown _userScopeTeardown;
  final AuthenticationAttemptGate _authenticationAttemptGate;
  final OnlineOperationGuard? _onlineOperationGuard;
  StreamSubscription<SessionInvalidationEvent>? _invalidationSubscription;
  bool _isSessionExitInProgress = false;
  int _sessionOperationGeneration = 0;

  SessionNotifier(
    this._authRepository,
    this._userScopeTeardown, {
    AuthenticationAttemptGate? authenticationAttemptGate,
    SessionInvalidationSignal? sessionInvalidationSignal,
    OnlineOperationGuard? onlineOperationGuard,
    bool autoInitialize = true,
  }) : _authenticationAttemptGate =
           authenticationAttemptGate ?? AuthenticationAttemptGate(),
       _onlineOperationGuard = onlineOperationGuard,
       super(const SessionData(state: SessionState.initial)) {
    _invalidationSubscription = sessionInvalidationSignal?.events.listen((_) {
      if (state.state == SessionState.unauthenticated ||
          state.pendingExitReason != null ||
          _isSessionExitInProgress) {
        return;
      }
      unawaited(handleForcedAuthenticationLoss());
    });
    if (autoInitialize) {
      _initializeSession();
    }
  }

  /// Every state change funnels through this setter, so the data-layer online
  /// guard mirrors session state exactly. Only a fully online session admits
  /// server mutations; offline, checking, refreshing, and signed-out states
  /// deny them.
  @override
  set state(SessionData value) {
    _onlineOperationGuard?.setOnline(value.state == SessionState.authenticated);
    super.state = value;
  }

  @override
  void dispose() {
    final subscription = _invalidationSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  bool _publishAuthenticated(
    UserEntity user, {
    required SessionState sessionState,
    String? errorMessage,
    int? expectedGeneration,
  }) {
    if (expectedGeneration != null &&
        !_isSessionOperationCurrent(expectedGeneration)) {
      return false;
    }
    _userScopeTeardown.activateUserScope(user.id);
    state = state.copyWith(
      state: sessionState,
      user: user,
      errorMessage: errorMessage,
      exitRequirement: UserScopeExitRequirement.none,
      pendingExitReason: null,
    );
    return true;
  }

  void _publishVerificationRequired(int expectedGeneration) {
    if (!_isSessionOperationCurrent(expectedGeneration)) return;
    state = state.copyWith(
      state: SessionState.checking,
      user: null,
      errorMessage:
          'Online session verification is required before account access can continue.',
      exitRequirement: UserScopeExitRequirement.none,
      pendingExitReason: null,
    );
  }

  int? _beginSessionOperation() {
    if (_isSessionExitInProgress ||
        state.pendingExitReason != null ||
        _authenticationAttemptGate.isActive) {
      return null;
    }
    _sessionOperationGeneration += 1;
    return _sessionOperationGeneration;
  }

  bool _isSessionOperationCurrent(int generation) {
    return !_isSessionExitInProgress &&
        state.pendingExitReason == null &&
        generation == _sessionOperationGeneration;
  }

  /// Initialize session on app startup
  Future<void> _initializeSession({bool isStartup = true}) async {
    final generation = _beginSessionOperation();
    if (generation == null) return;
    state = state.copyWith(
      state: SessionState.checking,
      errorMessage: null,
      exitRequirement: UserScopeExitRequirement.none,
      pendingExitReason: null,
    );

    try {
      final hasPendingCleanup = await _authRepository.hasPendingAuthCleanup();
      if (!_isSessionOperationCurrent(generation)) return;
      if (hasPendingCleanup) {
        await _authenticationAttemptGate.suspendAndDrain();
        // Finishing an exit interrupted by process death is still an exit:
        // clear the native Google session here too, so a forced loss that
        // completes on restart leaves the same clean state as one that ran to
        // completion in `_exitSession`.
        unawaited(_authRepository.signOutFromGoogle());
        try {
          await _authRepository.clearAuthData();
          if (!_isSessionOperationCurrent(generation)) return;
          _authenticationAttemptGate.resume();
          state = const SessionData(state: SessionState.unauthenticated);
        } catch (_) {
          if (!_isSessionOperationCurrent(generation)) return;
          state = const SessionData(
            state: SessionState.checking,
            errorMessage:
                'Local sign-out cleanup is incomplete. Retry before using another account.',
            exitRequirement: UserScopeExitRequirement.localCredentialCleanup,
            pendingExitReason: UserScopeExitReason.forcedAuthenticationLoss,
          );
        }
        return;
      }
    } catch (_) {
      if (!_isSessionOperationCurrent(generation)) return;
      await _authenticationAttemptGate.suspendAndDrain();
      if (!_isSessionOperationCurrent(generation)) return;
      state = const SessionData(
        state: SessionState.checking,
        errorMessage: 'Account cleanup status could not be verified.',
        exitRequirement: UserScopeExitRequirement.accountCleanup,
        pendingExitReason: UserScopeExitReason.forcedAuthenticationLoss,
      );
      return;
    }

    try {
      // Parallelize independent async disk reads to optimize startup latency
      final results = await Future.wait([
        _authRepository.getCurrentUser(),
        _authRepository.needsTokenRefresh(),
        _authRepository.canStayLoggedInOffline(),
      ]);
      if (!_isSessionOperationCurrent(generation)) return;

      final userData = results[0] as UserEntity?;
      final needsRefresh = results[1] as bool;
      final canStayOffline = results[2] as bool;

      if (userData != null) {
        if (canStayOffline) {
          if (needsRefresh) {
            if (isStartup) {
              // Optimistically admit the user offline immediately so the app opens instantly.
              _publishAuthenticated(
                userData,
                sessionState: SessionState.authenticatedOffline,
                expectedGeneration: generation,
              );
              // Trigger token refresh asynchronously in the background.
              unawaited(_refreshTokenBackground(generation, userData));
            } else {
              // Non-startup: block and refresh with traditional UI.
              await _refreshToken(generation);
            }
          } else {
            // The access token is still fresh! We can admit them fully online.
            _publishAuthenticated(
              userData,
              sessionState: SessionState.authenticated,
              expectedGeneration: generation,
            );
            if (isStartup) {
              // Verify session validation in the background without blocking.
              unawaited(_validateSessionBackground(generation, userData));
            } else {
              // Non-startup: block and validate.
              final validation = await _authRepository.validateSession();
              if (!_isSessionOperationCurrent(generation)) return;
              switch (validation) {
                case SessionValidationStatus.valid:
                  break;
                case SessionValidationStatus.invalid:
                  await handleForcedAuthenticationLoss();
                  break;
                case SessionValidationStatus.unavailable:
                  _publishAuthenticated(
                    userData,
                    sessionState: SessionState.authenticatedOffline,
                    errorMessage:
                        'Offline mode - limited functionality available',
                    expectedGeneration: generation,
                  );
                  break;
              }
            }
          }
        } else {
          // 7-day offline sync window exceeded. We MUST block and verify with backend.
          state = state.copyWith(
            state: SessionState.checking,
            errorMessage: 'Verifying session online...',
          );
          final validation = await _authRepository.validateSession();
          if (!_isSessionOperationCurrent(generation)) return;
          switch (validation) {
            case SessionValidationStatus.valid:
              _publishAuthenticated(
                userData,
                sessionState: SessionState.authenticated,
                expectedGeneration: generation,
              );
              break;
            case SessionValidationStatus.invalid:
              await handleForcedAuthenticationLoss();
              break;
            case SessionValidationStatus.unavailable:
              _publishVerificationRequired(generation);
              break;
          }
        }
        return;
      }

      // Cached identity and credentials are one admission unit. Orphan
      // credentials cannot authorize a protected or offline subtree.
      await handleForcedAuthenticationLoss();
    } on AuthSessionInvalid {
      if (_isSessionOperationCurrent(generation)) {
        await handleForcedAuthenticationLoss();
      }
    } on AuthSessionUnavailable {
      if (!_isSessionOperationCurrent(generation)) return;
      final userData = await _authRepository.getCurrentUser();
      if (!_isSessionOperationCurrent(generation)) return;
      final canStayOffline =
          userData != null && await _authRepository.canStayLoggedInOffline();
      if (!_isSessionOperationCurrent(generation)) return;
      if (userData != null && canStayOffline) {
        _publishAuthenticated(
          userData,
          sessionState: SessionState.authenticatedOffline,
          errorMessage: 'Connection failed - offline mode enabled',
          expectedGeneration: generation,
        );
      } else {
        _publishVerificationRequired(generation);
      }
    } catch (_) {
      if (!_isSessionOperationCurrent(generation)) return;
      state = state.copyWith(
        state: SessionState.checking,
        errorMessage:
            'Account data could not be verified. Retry when connectivity is available.',
        user: null,
      );
    }
  }

  /// Refresh the access token
  Future<void> _refreshToken(int generation) async {
    if (!_isSessionOperationCurrent(generation)) return;
    try {
      state = state.copyWith(
        state: SessionState.refreshing,
        errorMessage: null,
      );

      final user = await _authRepository.refreshToken();
      _publishAuthenticated(
        user,
        sessionState: SessionState.authenticated,
        expectedGeneration: generation,
      );
    } on AuthSessionInvalid {
      if (!_isSessionOperationCurrent(generation)) return;
      await handleForcedAuthenticationLoss();
    } on AuthSessionUnavailable {
      if (!_isSessionOperationCurrent(generation)) return;
      final userData = await _authRepository.getCurrentUser();
      if (!_isSessionOperationCurrent(generation)) return;
      final canStayOffline =
          userData != null && await _authRepository.canStayLoggedInOffline();
      if (!_isSessionOperationCurrent(generation)) return;
      if (userData != null && canStayOffline) {
        _publishAuthenticated(
          userData,
          sessionState: SessionState.authenticatedOffline,
          errorMessage: 'Connection failed - offline mode enabled',
          expectedGeneration: generation,
        );
      } else {
        _publishVerificationRequired(generation);
      }
    } catch (_) {
      if (!_isSessionOperationCurrent(generation)) return;
      _publishVerificationRequired(generation);
    }
  }

  /// Run token refresh in the background to avoid blocking the main thread / startup
  Future<void> _refreshTokenBackground(
    int generation,
    UserEntity userData,
  ) async {
    try {
      final user = await _authRepository.refreshToken();
      if (!_isSessionOperationCurrent(generation)) return;
      _publishAuthenticated(
        user,
        sessionState: SessionState.authenticated,
        expectedGeneration: generation,
      );
    } on AuthSessionInvalid {
      if (!_isSessionOperationCurrent(generation)) return;
      await handleForcedAuthenticationLoss();
    } catch (e) {
      log('SessionProvider: Background token refresh failed: $e');
    }
  }

  /// Run session validation in the background to avoid blocking startup
  Future<void> _validateSessionBackground(
    int generation,
    UserEntity userData,
  ) async {
    try {
      final validation = await _authRepository.validateSession();
      if (!_isSessionOperationCurrent(generation)) return;
      switch (validation) {
        case SessionValidationStatus.valid:
          break;
        case SessionValidationStatus.invalid:
          await handleForcedAuthenticationLoss();
          break;
        case SessionValidationStatus.unavailable:
          await _handleUnavailableBackground(generation, userData);
          break;
      }
    } catch (e) {
      log('SessionProvider: Background session validation failed: $e');
      await _handleUnavailableBackground(generation, userData);
    }
  }

  Future<void> _handleUnavailableBackground(
    int generation,
    UserEntity userData,
  ) async {
    final canStayOffline = await _authRepository.canStayLoggedInOffline();
    if (!_isSessionOperationCurrent(generation)) return;
    if (canStayOffline) {
      _publishAuthenticated(
        userData,
        sessionState: SessionState.authenticatedOffline,
        errorMessage: 'Connection failed - offline mode enabled',
        expectedGeneration: generation,
      );
    } else {
      _publishVerificationRequired(generation);
    }
  }

  /// Called after successful login
  bool onLoginSuccess(UserEntity user) {
    // Validate user data
    if (user.email.isEmpty) {
      log('SessionProvider: Invalid user data received');
      return false;
    }

    if (state.pendingExitReason != null || _isSessionExitInProgress) {
      state = state.copyWith(
        errorMessage: 'Finish the pending account cleanup before signing in.',
      );
      return false;
    }

    final existingUser = state.user;
    if (existingUser != null && existingUser.id != user.id) {
      state = state.copyWith(
        errorMessage: 'Sign out before using another account.',
      );
      return false;
    }

    _sessionOperationGeneration += 1;
    _publishAuthenticated(user, sessionState: SessionState.authenticated);
    return true;
  }

  int? beginAuthenticationAttempt() {
    if (blocksNewAuthentication) return null;
    return _sessionOperationGeneration;
  }

  bool completeAuthenticationAttempt(UserEntity user, int admission) {
    if (admission != _sessionOperationGeneration || blocksNewAuthentication) {
      return false;
    }
    return onLoginSuccess(user);
  }

  Future<void> updateProfilePicture({
    required String ownerUserId,
    required String path,
    required String type,
  }) async {
    final currentUser = state.user;
    if (currentUser == null || currentUser.id != ownerUserId) return;

    final updatedUser = currentUser.copyWith(
      profilePicturePath: path,
      profilePictureType: type,
    );
    await _authRepository.updateCurrentUser(updatedUser);
    // Re-merge only the owned avatar fields onto the latest session user. A
    // name edit that committed during the persist above must be preserved, not
    // clobbered by this pre-await snapshot.
    final latestUser = state.user;
    if (latestUser == null || latestUser.id != ownerUserId) return;
    final committedUser = latestUser.copyWith(
      profilePicturePath: path,
      profilePictureType: type,
    );
    state = state.copyWith(user: committedUser);
    if (committedUser != updatedUser) {
      await _authRepository.updateCurrentUser(committedUser);
    }
  }

  /// Commits a server-confirmed profile edit into session and cached state.
  ///
  /// Only the fields this operation owns (first/last name) are merged; avatar
  /// fields belong to the dedicated upload pipeline, and cached email/creation
  /// metadata stays local. A response for a different or stale owner is
  /// discarded rather than applied across accounts.
  Future<void> applyProfileUpdate({
    required String ownerUserId,
    required UserEntity updatedUser,
  }) async {
    final currentUser = state.user;
    if (currentUser == null ||
        currentUser.id != ownerUserId ||
        updatedUser.id != ownerUserId) {
      return;
    }

    final mergedUser = currentUser.copyWith(
      firstName: updatedUser.firstName,
      lastName: updatedUser.lastName,
    );
    await _authRepository.updateCurrentUser(mergedUser);
    // Re-merge only the owned name fields onto the latest session user so a
    // concurrent avatar commit during the persist above is preserved rather
    // than clobbered by this pre-await snapshot.
    final latestUser = state.user;
    if (latestUser == null || latestUser.id != ownerUserId) return;
    final committedUser = latestUser.copyWith(
      firstName: updatedUser.firstName,
      lastName: updatedUser.lastName,
    );
    state = state.copyWith(user: committedUser);
    if (committedUser != mergedUser) {
      await _authRepository.updateCurrentUser(committedUser);
    }
  }

  /// Re-reads the server's email verification state and commits only that flag.
  ///
  /// Verification normally completes in a browser, often on another device, so
  /// the app has no other signal that it happened. Only emailVerified is
  /// merged; name and avatar stay owned by their own flows, and a response for
  /// a different or stale owner is discarded rather than applied.
  Future<void> refreshVerificationState() async {
    final currentUser = state.user;
    if (currentUser == null) return;

    final UserEntity serverUser;
    try {
      serverUser = await _authRepository.refreshCurrentUser();
    } catch (_) {
      // Best effort: a failed refresh simply leaves the banner as it was.
      return;
    }
    if (serverUser.id != currentUser.id) return;

    final latestUser = state.user;
    if (latestUser == null ||
        latestUser.id != currentUser.id ||
        latestUser.emailVerified == serverUser.emailVerified) {
      return;
    }

    final committedUser = latestUser.copyWith(
      emailVerified: serverUser.emailVerified,
    );
    state = state.copyWith(user: committedUser);
    await _authRepository.updateCurrentUser(committedUser);
  }

  /// Requests another verification email. Errors (including the server-side
  /// rate limit) propagate so the caller can surface them.
  Future<void> resendVerificationEmail() {
    return _authRepository.resendVerificationEmail();
  }

  /// Called to logout user. An active or unsaved workout requires an explicit
  /// decision before credentials or user state are cleared.
  Future<UserScopeTeardownResult> logout({UserScopeExitDecision? decision}) {
    return _exitSession(
      reason: UserScopeExitReason.voluntaryLogout,
      decision: decision,
      requestRemoteLogout: true,
    );
  }

  Future<UserScopeTeardownResult> handleForcedAuthenticationLoss({
    UserScopeExitDecision? decision,
  }) {
    return _exitSession(
      reason: UserScopeExitReason.forcedAuthenticationLoss,
      decision: decision,
      requestRemoteLogout: false,
    );
  }

  Future<UserScopeTeardownResult> resolvePendingExit(
    UserScopeExitDecision decision,
  ) {
    final reason = state.pendingExitReason;
    if (reason == null) {
      return Future<UserScopeTeardownResult>.value(
        const UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.none,
          message: 'There is no pending account action.',
        ),
      );
    }
    return _exitSession(
      reason: reason,
      decision: decision,
      requestRemoteLogout: reason == UserScopeExitReason.voluntaryLogout,
    );
  }

  void cancelPendingExit() {
    if (_isSessionExitInProgress ||
        state.pendingExitReason == null ||
        state.pendingExitReason ==
            UserScopeExitReason.forcedAuthenticationLoss) {
      return;
    }
    _sessionOperationGeneration += 1;
    state = state.copyWith(
      errorMessage: null,
      exitRequirement: UserScopeExitRequirement.none,
      pendingExitReason: null,
    );
  }

  Future<UserScopeTeardownResult> _exitSession({
    required UserScopeExitReason reason,
    required bool requestRemoteLogout,
    UserScopeExitDecision? decision,
  }) async {
    if (_isSessionExitInProgress) {
      return const UserScopeTeardownResult.blocked(
        requirement: UserScopeExitRequirement.none,
        message: 'Account cleanup is already in progress.',
      );
    }

    _sessionOperationGeneration += 1;

    final isForcedAuthenticationLoss =
        reason == UserScopeExitReason.forcedAuthenticationLoss;
    var cleanupMarkerPersisted = false;
    if (isForcedAuthenticationLoss) {
      try {
        // A backend-rejected or otherwise invalid session must remain
        // fail-closed if local workout recovery blocks teardown and the process
        // exits before credentials can be fully cleared.
        await _authRepository.markAuthCleanupPending();
        cleanupMarkerPersisted = true;
      } catch (_) {
        await _authenticationAttemptGate.suspendAndDrain();
        const result = UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.accountCleanup,
          message:
              'Account cleanup could not be secured for restart. Retry before continuing.',
        );
        state = state.copyWith(
          state: SessionState.checking,
          errorMessage: result.message,
          exitRequirement: result.requirement,
          pendingExitReason: reason,
        );
        return result;
      }
    }

    late final UserScopeExitRequirement requirement;
    try {
      requirement = _userScopeTeardown.requirementFor(reason);
    } catch (_) {
      const result = UserScopeTeardownResult.blocked(
        requirement: UserScopeExitRequirement.accountCleanup,
        message: 'Account cleanup could not start. Please retry.',
      );
      state = state.copyWith(
        errorMessage: result.message,
        exitRequirement: result.requirement,
        pendingExitReason: reason,
      );
      return result;
    }
    if (requirement != UserScopeExitRequirement.none && decision == null) {
      state = state.copyWith(
        exitRequirement: requirement,
        pendingExitReason: reason,
      );
      return UserScopeTeardownResult.decisionRequired(requirement);
    }

    final previousState = state;
    _isSessionExitInProgress = true;
    state = state.copyWith(
      state: SessionState.checking,
      errorMessage: null,
      exitRequirement: UserScopeExitRequirement.none,
      pendingExitReason: reason,
    );

    try {
      final teardown = await _userScopeTeardown.teardown(
        reason: reason,
        decision: decision,
      );
      if (!teardown.isCompleted) {
        final userId = previousState.user?.id;
        if (userId != null) {
          _userScopeTeardown.activateUserScope(userId);
        }
        state = previousState.copyWith(
          errorMessage: teardown.message,
          exitRequirement: teardown.requirement,
          pendingExitReason: reason,
        );
        return teardown;
      }

      await _authenticationAttemptGate.suspendAndDrain();

      try {
        if (!cleanupMarkerPersisted) {
          await _authRepository.markAuthCleanupPending();
        }
      } catch (_) {
        const result = UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.accountCleanup,
          message:
              'Account cleanup could not be secured for restart. Retry before using another account.',
        );
        state = previousState.copyWith(
          state: SessionState.checking,
          errorMessage: result.message,
          exitRequirement: result.requirement,
          pendingExitReason: reason,
        );
        return result;
      }

      // Clear the native Google session on every exit — voluntary logout and
      // forced loss alike — so the next Google sign-in shows the account
      // chooser instead of silently reusing the signed-out account. Fire and
      // forget: a slow native sign-out must never block credential teardown.
      unawaited(_authRepository.signOutFromGoogle());

      if (requestRemoteLogout) {
        try {
          await _authRepository.logout();
        } catch (_) {
          // Remote logout is best effort; local teardown has already passed.
        }
      }

      try {
        await _authRepository.clearAuthData();
      } catch (_) {
        const result = UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.localCredentialCleanup,
          message:
              'Local sign-out cleanup is incomplete. Retry before using another account.',
        );
        state = previousState.copyWith(
          state: SessionState.checking,
          errorMessage: result.message,
          exitRequirement: result.requirement,
          pendingExitReason: reason,
        );
        return result;
      }
      state = const SessionData(state: SessionState.unauthenticated);
      _authenticationAttemptGate.resume();
      return const UserScopeTeardownResult.completed();
    } catch (_) {
      final userId = previousState.user?.id;
      if (userId != null) {
        _userScopeTeardown.activateUserScope(userId);
      }
      const result = UserScopeTeardownResult.blocked(
        requirement: UserScopeExitRequirement.accountCleanup,
        message: 'Account cleanup failed. Please retry.',
      );
      state = previousState.copyWith(
        errorMessage: result.message,
        exitRequirement: result.requirement,
        pendingExitReason: reason,
      );
      return result;
    } finally {
      _isSessionExitInProgress = false;
    }
  }

  /// Check if user is authenticated (either online or offline)
  bool get isAuthenticated =>
      state.state == SessionState.authenticated ||
      state.state == SessionState.authenticatedOffline;

  /// Prevents another login while A is authenticated or its local credential
  /// cleanup is still unresolved.
  bool get blocksNewAuthentication =>
      state.state != SessionState.unauthenticated ||
      state.user != null ||
      state.pendingExitReason != null ||
      _isSessionExitInProgress;

  /// Check if user has full online access
  bool get isFullyAuthenticated => state.state == SessionState.authenticated;

  /// Check if user is in offline mode
  bool get isOfflineMode => state.state == SessionState.authenticatedOffline;

  /// Check if session is being checked/initialized
  bool get isLoading =>
      state.state == SessionState.checking ||
      state.state == SessionState.refreshing;

  /// Force refresh session (useful for pull-to-refresh scenarios)
  Future<void> refreshSession() async {
    await _initializeSession(isStartup: false);
  }

  /// Force clear and reinitialize session (useful for debugging)
  Future<void> forceReinitialize() async {
    log('SessionProvider: Force reinitializing session');
    final result = await handleForcedAuthenticationLoss();
    if (result.isCompleted) {
      state = const SessionData(state: SessionState.initial);
      await _initializeSession(isStartup: true);
    }
  }

  /// Validate current session (can be called periodically)
  Future<void> validateSession() async {
    if (!isAuthenticated) return;
    final generation = _beginSessionOperation();
    if (generation == null) return;

    try {
      final validation = await _authRepository.validateSession();
      if (!_isSessionOperationCurrent(generation)) return;
      switch (validation) {
        case SessionValidationStatus.valid:
          final user = state.user;
          if (user != null) {
            _publishAuthenticated(
              user,
              sessionState: SessionState.authenticated,
              expectedGeneration: generation,
            );
          }
          break;
        case SessionValidationStatus.invalid:
          await handleForcedAuthenticationLoss();
          break;
        case SessionValidationStatus.unavailable:
          final user = state.user;
          final canStayOffline =
              user != null && await _authRepository.canStayLoggedInOffline();
          if (!_isSessionOperationCurrent(generation)) return;
          if (user != null && canStayOffline) {
            _publishAuthenticated(
              user,
              sessionState: SessionState.authenticatedOffline,
              errorMessage: 'Offline mode - limited functionality available',
              expectedGeneration: generation,
            );
          } else {
            _publishVerificationRequired(generation);
          }
          break;
      }
    } on AuthSessionInvalid {
      if (!_isSessionOperationCurrent(generation)) return;
      await handleForcedAuthenticationLoss();
    } on AuthSessionUnavailable {
      if (!_isSessionOperationCurrent(generation)) return;
      final user = state.user;
      final canStayOffline =
          user != null && await _authRepository.canStayLoggedInOffline();
      if (!_isSessionOperationCurrent(generation)) return;
      if (user != null && canStayOffline) {
        _publishAuthenticated(
          user,
          sessionState: SessionState.authenticatedOffline,
          errorMessage: 'Offline mode - limited functionality available',
          expectedGeneration: generation,
        );
      } else {
        _publishVerificationRequired(generation);
      }
    } catch (_) {
      if (!_isSessionOperationCurrent(generation)) return;
      _publishVerificationRequired(generation);
    }
  }
}

final StateNotifierProvider<SessionNotifier, SessionData> sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionData>((ref) {
      final authRepository = ref.watch(authRepositoryProvider);
      final teardown = ref.watch(userScopeTeardownProvider);
      return SessionNotifier(
        authRepository,
        teardown,
        authenticationAttemptGate: ref.watch(authenticationAttemptGateProvider),
        sessionInvalidationSignal: ref.watch(sessionInvalidationSignalProvider),
        onlineOperationGuard: ref.watch(onlineOperationGuardProvider),
      );
    });

// Convenience providers
final isAuthenticatedProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session.state == SessionState.authenticated ||
      session.state == SessionState.authenticatedOffline;
});

final isFullyAuthenticatedProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session.state == SessionState.authenticated;
});

final isOfflineModeProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session.state == SessionState.authenticatedOffline;
});

final currentUserProvider = Provider<UserEntity?>((ref) {
  final session = ref.watch(sessionProvider);
  return session.user;
});

final sessionStateProvider = Provider<SessionState>((ref) {
  final session = ref.watch(sessionProvider);
  return session.state;
});
