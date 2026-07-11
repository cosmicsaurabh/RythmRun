import 'dart:async';

/// Serializes long-running work against the currently authenticated user.
///
/// A teardown first calls [suspendAndDrain]. Suspension rejects new leases
/// immediately, while the returned future completes only after every lease
/// that was already granted has been released. The next user scope may then
/// be opened with [activate].
class UserScopeOperationGate {
  int? _activeUserId;
  bool _isSuspended = true;
  int _activeLeaseCount = 0;
  Completer<void>? _drainCompleter;

  int? get activeUserId => _activeUserId;

  bool get isSuspended => _isSuspended;

  int get activeLeaseCount => _activeLeaseCount;

  /// Opens the gate for [userId]. Switching users requires a completed drain.
  void activate(int userId) {
    if (userId <= 0) {
      throw ArgumentError.value(userId, 'userId', 'Must be positive');
    }

    if (!_isSuspended) {
      if (_activeUserId == userId) {
        return;
      }
      throw StateError(
        'Suspend and drain the current user scope before activating another.',
      );
    }

    if (_activeLeaseCount != 0) {
      throw StateError(
        'Cannot activate a user scope while previous operations are draining.',
      );
    }

    _activeUserId = userId;
    _isSuspended = false;
    _drainCompleter = null;
  }

  /// Returns a lease only when [userId] owns the currently active scope.
  UserScopeOperationLease? tryAcquire(int userId) {
    if (_isSuspended || _activeUserId != userId) {
      return null;
    }

    _activeLeaseCount += 1;
    return UserScopeOperationLease._(this, userId);
  }

  /// Rejects new work and completes after all previously granted leases end.
  Future<void> suspendAndDrain() {
    _isSuspended = true;
    _activeUserId = null;

    if (_activeLeaseCount == 0) {
      return Future<void>.value();
    }

    final existingDrain = _drainCompleter;
    if (existingDrain != null) {
      return existingDrain.future;
    }

    final drainCompleter = Completer<void>();
    _drainCompleter = drainCompleter;
    return drainCompleter.future;
  }

  void _release(UserScopeOperationLease lease) {
    if (lease._isReleased) {
      return;
    }

    lease._isReleased = true;
    _activeLeaseCount -= 1;
    if (_activeLeaseCount < 0) {
      throw StateError('User-scope operation lease count became negative.');
    }

    if (_isSuspended && _activeLeaseCount == 0) {
      final drainCompleter = _drainCompleter;
      if (drainCompleter != null && !drainCompleter.isCompleted) {
        drainCompleter.complete();
      }
    }
  }
}

/// A single in-flight operation admitted by [UserScopeOperationGate].
class UserScopeOperationLease {
  final UserScopeOperationGate _gate;
  final int userId;
  bool _isReleased = false;

  UserScopeOperationLease._(this._gate, this.userId);

  bool get isReleased => _isReleased;

  /// Releases the lease. Repeated calls are safe no-ops.
  void release() {
    _gate._release(this);
  }
}
