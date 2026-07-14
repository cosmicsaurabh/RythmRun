import '../network/auth_failures.dart';

/// Single source of truth in the data layer for whether the current session may
/// perform online-only operations.
///
/// Offline (or unauthenticated/checking) mode denies server mutations up front
/// with a clear, non-alarming message instead of letting them reach the network
/// and fail generically. This is defense in depth beneath the presentation-tier
/// `FeatureGate`: the session coordinator is the only writer, and it flips this
/// guard on every state transition, so a mutation begun as connectivity drops
/// is still refused (IP-2.3).
class OnlineOperationGuard {
  bool _isOnline = false;

  /// Whether a fully online, verified session is currently active.
  bool get isOnline => _isOnline;

  /// Updated by the session coordinator whenever session state changes.
  void setOnline(bool online) {
    _isOnline = online;
  }

  /// Throws a typed offline failure unless a fully online session is active.
  void requireOnline() {
    if (_isOnline) return;
    throw const AuthSessionUnavailable(
      AuthSessionUnavailableReason.offlineMode,
    );
  }
}
