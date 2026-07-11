enum UserScopeExitReason {
  voluntaryLogout,
  forcedAuthenticationLoss,
  accountSwitch,
}

enum UserScopeExitDecision {
  finishWorkout,
  retrySave,
  discardWorkout,
  retryTrackingCleanup,
  retryCredentialCleanup,
  retryAccountCleanup,
}

enum UserScopeExitRequirement {
  none,
  activeWorkout,
  unsavedWorkout,
  trackingCleanup,
  localCredentialCleanup,
  accountCleanup,
}

enum UserScopeTeardownStatus { completed, decisionRequired, blocked }

class UserScopeTeardownResult {
  final UserScopeTeardownStatus status;
  final UserScopeExitRequirement requirement;
  final String? message;

  const UserScopeTeardownResult._({
    required this.status,
    this.requirement = UserScopeExitRequirement.none,
    this.message,
  });

  const UserScopeTeardownResult.completed()
    : this._(status: UserScopeTeardownStatus.completed);

  const UserScopeTeardownResult.decisionRequired(
    UserScopeExitRequirement requirement,
  ) : this._(
        status: UserScopeTeardownStatus.decisionRequired,
        requirement: requirement,
      );

  const UserScopeTeardownResult.blocked({
    required UserScopeExitRequirement requirement,
    required String message,
  }) : this._(
         status: UserScopeTeardownStatus.blocked,
         requirement: requirement,
         message: message,
       );

  bool get isCompleted => status == UserScopeTeardownStatus.completed;
}

abstract interface class UserScopeTeardown {
  UserScopeExitRequirement requirementFor(UserScopeExitReason reason);

  Future<UserScopeTeardownResult> teardown({
    required UserScopeExitReason reason,
    UserScopeExitDecision? decision,
  });

  void activateUserScope(String userId);
}

typedef UserScopeBoolReader = bool Function();
typedef UserScopeAsyncBoolAction = Future<bool> Function();
typedef UserScopeAsyncAction = Future<void> Function();
typedef UserScopeVoidAction = void Function();
typedef UserScopeActivateAction = void Function(String userId);

/// Serializes live-workout finalization, sync draining, and cache teardown.
///
/// The coordinator deliberately has no Riverpod dependency. Production wires
/// provider callbacks around it, while tests can exercise the transition
/// contract without a widget tree.
class DefaultUserScopeTeardown implements UserScopeTeardown {
  final UserScopeBoolReader _hasActiveWorkout;
  final UserScopeBoolReader _hasUnsavedWorkout;
  final UserScopeBoolReader _hasPendingTrackingCleanup;
  final UserScopeAsyncBoolAction _quiesceTrackingOperations;
  final UserScopeAsyncBoolAction _finishWorkout;
  final UserScopeAsyncBoolAction _retryWorkoutSave;
  final UserScopeAsyncBoolAction _retryTrackingCleanup;
  final UserScopeAsyncAction _discardWorkout;
  final UserScopeAsyncAction _suspendAndDrainWork;
  final UserScopeVoidAction _invalidateUserState;
  final UserScopeActivateAction _activateWork;

  bool _isTearingDown = false;

  DefaultUserScopeTeardown({
    required UserScopeBoolReader hasActiveWorkout,
    required UserScopeBoolReader hasUnsavedWorkout,
    required UserScopeBoolReader hasPendingTrackingCleanup,
    required UserScopeAsyncBoolAction quiesceTrackingOperations,
    required UserScopeAsyncBoolAction finishWorkout,
    required UserScopeAsyncBoolAction retryWorkoutSave,
    required UserScopeAsyncBoolAction retryTrackingCleanup,
    required UserScopeAsyncAction discardWorkout,
    required UserScopeAsyncAction suspendAndDrainWork,
    required UserScopeVoidAction invalidateUserState,
    required UserScopeActivateAction activateWork,
  }) : _hasActiveWorkout = hasActiveWorkout,
       _hasUnsavedWorkout = hasUnsavedWorkout,
       _hasPendingTrackingCleanup = hasPendingTrackingCleanup,
       _quiesceTrackingOperations = quiesceTrackingOperations,
       _finishWorkout = finishWorkout,
       _retryWorkoutSave = retryWorkoutSave,
       _retryTrackingCleanup = retryTrackingCleanup,
       _discardWorkout = discardWorkout,
       _suspendAndDrainWork = suspendAndDrainWork,
       _invalidateUserState = invalidateUserState,
       _activateWork = activateWork;

  @override
  UserScopeExitRequirement requirementFor(UserScopeExitReason reason) {
    if (_hasUnsavedWorkout()) {
      return UserScopeExitRequirement.unsavedWorkout;
    }
    if (_hasPendingTrackingCleanup()) {
      return UserScopeExitRequirement.trackingCleanup;
    }
    if (_hasActiveWorkout() &&
        reason != UserScopeExitReason.forcedAuthenticationLoss) {
      return UserScopeExitRequirement.activeWorkout;
    }
    return UserScopeExitRequirement.none;
  }

  @override
  Future<UserScopeTeardownResult> teardown({
    required UserScopeExitReason reason,
    UserScopeExitDecision? decision,
  }) async {
    if (_isTearingDown) {
      return const UserScopeTeardownResult.blocked(
        requirement: UserScopeExitRequirement.accountCleanup,
        message: 'Account cleanup is already in progress.',
      );
    }

    final requirement = requirementFor(reason);
    if (requirement != UserScopeExitRequirement.none && decision == null) {
      return UserScopeTeardownResult.decisionRequired(requirement);
    }

    _isTearingDown = true;
    try {
      if (!await _quiesceTrackingOperations()) {
        return const UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.trackingCleanup,
          message:
              'Location tracking is still shutting down. Retry cleanup before account exit.',
        );
      }

      final postQuiescenceRequirement = requirementFor(reason);
      if (postQuiescenceRequirement != UserScopeExitRequirement.none &&
          decision == null) {
        return UserScopeTeardownResult.decisionRequired(
          postQuiescenceRequirement,
        );
      }

      if (_hasUnsavedWorkout()) {
        if (decision == UserScopeExitDecision.discardWorkout) {
          await _discardWorkout();
        } else if (decision == UserScopeExitDecision.retrySave) {
          if (!await _retryWorkoutSave()) {
            return const UserScopeTeardownResult.blocked(
              requirement: UserScopeExitRequirement.unsavedWorkout,
              message:
                  'The workout is still not saved. Retry or explicitly discard it.',
            );
          }
        } else {
          return const UserScopeTeardownResult.decisionRequired(
            UserScopeExitRequirement.unsavedWorkout,
          );
        }
      }

      if (_hasPendingTrackingCleanup()) {
        if (decision != UserScopeExitDecision.retryTrackingCleanup) {
          return const UserScopeTeardownResult.decisionRequired(
            UserScopeExitRequirement.trackingCleanup,
          );
        }
        if (!await _retryTrackingCleanup() || _hasPendingTrackingCleanup()) {
          return const UserScopeTeardownResult.blocked(
            requirement: UserScopeExitRequirement.trackingCleanup,
            message:
                'Location tracking is still shutting down. Retry cleanup before account exit.',
          );
        }
      }

      if (_hasActiveWorkout()) {
        if (decision == UserScopeExitDecision.discardWorkout) {
          await _discardWorkout();
        } else {
          final didSave = await _finishWorkout();
          if (_hasUnsavedWorkout()) {
            return const UserScopeTeardownResult.blocked(
              requirement: UserScopeExitRequirement.unsavedWorkout,
              message:
                  'The workout could not be saved. Retry or explicitly discard it.',
            );
          }
          if (_hasPendingTrackingCleanup()) {
            return const UserScopeTeardownResult.blocked(
              requirement: UserScopeExitRequirement.trackingCleanup,
              message:
                  'The workout was finalized, but location tracking is still shutting down. Retry cleanup.',
            );
          }
          if (!didSave) {
            return const UserScopeTeardownResult.blocked(
              requirement: UserScopeExitRequirement.unsavedWorkout,
              message:
                  'The workout could not be saved. Retry or explicitly discard it.',
            );
          }
        }
      }

      if (_hasPendingTrackingCleanup()) {
        return const UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.trackingCleanup,
          message:
              'Location tracking is still shutting down. Retry cleanup before account exit.',
        );
      }

      if (_hasActiveWorkout()) {
        return const UserScopeTeardownResult.blocked(
          requirement: UserScopeExitRequirement.activeWorkout,
          message: 'The active workout must finish before account exit.',
        );
      }

      await _suspendAndDrainWork();
      _invalidateUserState();
      return const UserScopeTeardownResult.completed();
    } catch (_) {
      return const UserScopeTeardownResult.blocked(
        requirement: UserScopeExitRequirement.accountCleanup,
        message: 'Account cleanup failed. Please retry.',
      );
    } finally {
      _isTearingDown = false;
    }
  }

  @override
  void activateUserScope(String userId) {
    _activateWork(userId);
  }
}
