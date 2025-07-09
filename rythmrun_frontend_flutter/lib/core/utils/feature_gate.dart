import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/common/providers/session_provider.dart';

/// Feature gate utility to determine what features are available
/// based on current authentication state
class FeatureGate {
  static const String _offlineMessage =
      'This feature requires internet connection';
  static const String _authMessage = 'Please sign in to access this feature';

  /// Features available offline when user is authenticated
  static const List<String> _offlineFeatures = [
    'view_workouts',
    'track_workout',
    'view_profile',
    'view_statistics',
    'offline_settings',
  ];

  /// Features that require online authentication
  static const List<String> _onlineFeatures = [
    'sync_workouts',
    'social_features',
    'share_workout',
    'view_friends',
    'update_profile',
    'change_password',
  ];

  /// Check if a feature is available based on current session state
  static bool isFeatureAvailable(String feature, SessionState sessionState) {
    switch (sessionState) {
      case SessionState.authenticated:
        return true; // All features available

      case SessionState.authenticatedOffline:
        return _offlineFeatures.contains(feature);

      case SessionState.unauthenticated:
      case SessionState.initial:
      case SessionState.checking:
      case SessionState.refreshing:
        return false; // No features available
    }
  }

  /// Get user-friendly message for why a feature is unavailable
  static String getUnavailableMessage(
    String feature,
    SessionState sessionState,
  ) {
    switch (sessionState) {
      case SessionState.authenticated:
        return ''; // Should not be called when authenticated

      case SessionState.authenticatedOffline:
        if (_onlineFeatures.contains(feature)) {
          return _offlineMessage;
        }
        return 'Feature temporarily unavailable';

      case SessionState.unauthenticated:
      case SessionState.initial:
      case SessionState.checking:
      case SessionState.refreshing:
        return _authMessage;
    }
  }

  /// Check if feature requires online connection
  static bool requiresOnline(String feature) {
    return _onlineFeatures.contains(feature);
  }

  /// Check if feature works offline
  static bool worksOffline(String feature) {
    return _offlineFeatures.contains(feature);
  }
}

/// Provider to check feature availability
final featureGateProvider = Provider.family<bool, String>((ref, feature) {
  final sessionState = ref.watch(sessionStateProvider);
  return FeatureGate.isFeatureAvailable(feature, sessionState);
});

/// Provider to get unavailable message
final featureMessageProvider = Provider.family<String, String>((ref, feature) {
  final sessionState = ref.watch(sessionStateProvider);
  return FeatureGate.getUnavailableMessage(feature, sessionState);
});
