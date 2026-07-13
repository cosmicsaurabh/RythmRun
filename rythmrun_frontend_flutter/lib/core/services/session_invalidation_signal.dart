import 'dart:async';

enum SessionInvalidationReason { refreshRejected, passwordChanged }

class SessionInvalidationEvent {
  final SessionInvalidationReason reason;
  final int credentialRevision;

  const SessionInvalidationEvent({
    required this.reason,
    required this.credentialRevision,
  });
}

/// Process-local signal for turning an explicitly invalidated server session
/// into the existing coordinated account teardown. It never carries tokens.
class SessionInvalidationSignal {
  final StreamController<SessionInvalidationEvent> _controller =
      StreamController<SessionInvalidationEvent>.broadcast(sync: true);

  Stream<SessionInvalidationEvent> get events => _controller.stream;

  void emitRefreshRejected({required int credentialRevision}) {
    emit(
      reason: SessionInvalidationReason.refreshRejected,
      credentialRevision: credentialRevision,
    );
  }

  void emitPasswordChanged({required int credentialRevision}) {
    emit(
      reason: SessionInvalidationReason.passwordChanged,
      credentialRevision: credentialRevision,
    );
  }

  void emit({
    required SessionInvalidationReason reason,
    required int credentialRevision,
  }) {
    if (_controller.isClosed) return;
    _controller.add(
      SessionInvalidationEvent(
        reason: reason,
        credentialRevision: credentialRevision,
      ),
    );
  }

  Future<void> dispose() => _controller.close();
}
