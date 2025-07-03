import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/entities/user_entity.dart';
import '../../../core/di/injection_container.dart';

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
  final AuthRepository _authRepository;

  SessionNotifier(this._authRepository)
    : super(const SessionData(state: SessionState.initial)) {
    _initializeSession();
  }

  /// Initialize session on app startup
  Future<void> _initializeSession() async {
    state = state.copyWith(state: SessionState.checking);

    try {
      // Check if user is authenticated
      if (await _authRepository.isAuthenticated()) {
        final userData = await _authRepository.getCurrentUser();
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
      if (await _authRepository.needsTokenRefresh()) {
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

      final user = await _authRepository.refreshToken();

      state = state.copyWith(
        state: SessionState.authenticated,
        user: user,
        errorMessage: null,
      );
    } catch (e) {
      // Token refresh failed, user needs to login again
      await _clearSession();
    }
  }

  /// Clear session data and set to unauthenticated
  Future<void> _clearSession() async {
    await _authRepository.clearAuthData();
    state = state.copyWith(
      state: SessionState.unauthenticated,
      user: null,
      errorMessage: null,
    );
  }

  /// Called after successful login
  void onLoginSuccess(UserEntity user) {
    // Validate user data
    if (user.email.isEmpty) {
      log('SessionProvider: Invalid user data received');
      return;
    }

    // Ensure we're not already authenticated
    if (state.state == SessionState.authenticated) {
      log('SessionProvider: Already authenticated, updating user data');
    }

    state = state.copyWith(
      state: SessionState.authenticated,
      user: user,
      errorMessage: null,
    );
  }

  /// Called to logout user
  Future<void> logout() async {
    try {
      await _authRepository.logout();
    } catch (e) {
      // Even if server logout fails, we still clear local session
    } finally {
      await _clearSession();
    }
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

  /// Force clear and reinitialize session (useful for debugging)
  Future<void> forceReinitialize() async {
    log('SessionProvider: Force reinitializing session');
    await _authRepository.clearAuthData();
    state = const SessionData(state: SessionState.initial);
    await _initializeSession();
  }

  /// Validate current session (can be called periodically)
  Future<void> validateSession() async {
    if (!isAuthenticated) return;

    try {
      // Use repository to validate session
      final isValid = await _authRepository.validateSession();
      if (!isValid) {
        await _clearSession();
      }
    } catch (e) {
      await _clearSession();
    }
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionData>((
  ref,
) {
  final authRepository = ref.watch(authRepositoryProvider);
  return SessionNotifier(authRepository);
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
