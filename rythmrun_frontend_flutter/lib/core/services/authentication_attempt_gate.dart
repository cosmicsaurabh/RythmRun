import 'dart:async';

/// Serializes authentication mutations and lets account exit drain them before
/// locally persisted credentials are cleared.
class AuthenticationAttemptGate {
  bool _isSuspended = false;
  bool _isActive = false;
  Completer<void>? _drainCompleter;

  bool get isActive => _isActive;
  bool get isSuspended => _isSuspended;

  AuthenticationAttemptLease? tryAcquire() {
    if (_isSuspended || _isActive) return null;
    _isActive = true;
    return AuthenticationAttemptLease._(this);
  }

  Future<void> suspendAndDrain() {
    _isSuspended = true;
    if (!_isActive) return Future<void>.value();
    return (_drainCompleter ??= Completer<void>()).future;
  }

  void resume() {
    if (_isActive) {
      throw StateError('Cannot resume authentication while work is active.');
    }
    _isSuspended = false;
    _drainCompleter = null;
  }

  void _release(AuthenticationAttemptLease lease) {
    if (lease._isReleased) return;
    lease._isReleased = true;
    _isActive = false;
    final drainCompleter = _drainCompleter;
    if (_isSuspended && drainCompleter != null && !drainCompleter.isCompleted) {
      drainCompleter.complete();
    }
  }
}

class AuthenticationAttemptLease {
  final AuthenticationAttemptGate _gate;
  bool _isReleased = false;

  AuthenticationAttemptLease._(this._gate);

  void release() {
    _gate._release(this);
  }
}
