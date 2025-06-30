import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/auth_persistence_service.dart';
import '../../core/di/injection_container.dart';
import '../../domain/entities/user_entity.dart';
import '../../data/datasources/auth_remote_datasource.dart';

enum SessionState {
  initial,
  checking,
  authenticated,
  unauthenticated,
  refreshing,
}

class SessionData {
  final SessionState state;
  final UserEntity? user;
  final String? errorMessage;

  const SessionData({required this.state, this.user, this.errorMessage});

  SessionData copyWith({
    SessionState? state,
    UserEntity? user,
    String? errorMessage,
  }) {
    return SessionData(
      state: state ?? this.state,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SessionNotifier extends StateNotifier<SessionData> {
  final AuthRemoteDataSource _authDataSource;

  SessionNotifier(this._authDataSource)
    : super(const SessionData(state: SessionState.initial)) {
    _initializeSession();
  }

  /// Initialize session on app startup
  Future<void> _initializeSession() async {
    state = state.copyWith(state: SessionState.checking);

    try {
      // Check if session has exceeded maximum duration
      if (await AuthPersistenceService.isSessionExpired()) {
        await _clearSession();
        return;
      }

      // Check if we have a valid session
      if (await AuthPersistenceService.hasValidSession()) {
        final userData = await AuthPersistenceService.getUserData();
        if (userData != null) {
          state = state.copyWith(
            state: SessionState.authenticated,
            user: userData,
            errorMessage: null,
          );
          return;
        }
      }

      // Check if we need to refresh tokens
      if (await AuthPersistenceService.needsTokenRefresh()) {
        await _refreshToken();
        return;
      }

      // No valid session found
      state = state.copyWith(state: SessionState.unauthenticated);
    } catch (e) {
      // If anything goes wrong, clear session and go to unauthenticated
      await _clearSession();
    }
  }

  /// Refresh the access token
  Future<void> _refreshToken() async {
    try {
      state = state.copyWith(state: SessionState.refreshing);

      final authResponse = await _authDataSource.refreshToken();

      state = state.copyWith(
        state: SessionState.authenticated,
        user: authResponse.toUserEntity(),
        errorMessage: null,
      );
    } catch (e) {
      // Token refresh failed, user needs to login again
      await _clearSession();
    }
  }

  /// Clear session data and set to unauthenticated
  Future<void> _clearSession() async {
    await AuthPersistenceService.clearAuthData();
    state = state.copyWith(
      state: SessionState.unauthenticated,
      user: null,
      errorMessage: null,
    );
  }

  /// Called after successful login
  void onLoginSuccess(UserEntity user) {
    state = state.copyWith(
      state: SessionState.authenticated,
      user: user,
      errorMessage: null,
    );
  }

  /// Called to logout user
  Future<void> logout() async {
    try {
      await _authDataSource.logoutUser();
    } catch (e) {
      // Even if server logout fails, we still clear local session
      print('Server logout failed: $e');
    }

    await _clearSession();
  }

  /// Check if user is authenticated
  bool get isAuthenticated => state.state == SessionState.authenticated;

  /// Check if session is being checked/initialized
  bool get isLoading =>
      state.state == SessionState.checking ||
      state.state == SessionState.refreshing;

  /// Force refresh session (useful for pull-to-refresh scenarios)
  Future<void> refreshSession() async {
    await _initializeSession();
  }

  /// Validate current session (can be called periodically)
  Future<void> validateSession() async {
    if (!isAuthenticated) return;

    try {
      // Check if token is still valid
      if (!await AuthPersistenceService.hasValidSession()) {
        // Try to refresh
        if (await AuthPersistenceService.needsTokenRefresh()) {
          await _refreshToken();
        } else {
          await _clearSession();
        }
      }
    } catch (e) {
      await _clearSession();
    }
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionData>((
  ref,
) {
  final authDataSource = ref.watch(authRemoteDataSourceProvider);
  return SessionNotifier(authDataSource);
});

// Convenience providers
final isAuthenticatedProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session.state == SessionState.authenticated;
});

final currentUserProvider = Provider<UserEntity?>((ref) {
  final session = ref.watch(sessionProvider);
  return session.user;
});

final sessionStateProvider = Provider<SessionState>((ref) {
  final session = ref.watch(sessionProvider);
  return session.state;
});
