import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/entities/user_entity.dart';
import '../../../core/di/injection_container.dart';

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
      // Check if user is authenticated locally
      if (await _authRepository.isAuthenticated()) {
        final userData = await _authRepository.getCurrentUser();
        if (userData != null) {
          // Check if user can stay logged in offline (within 7-day sync window)
          final canStayOffline = await _authRepository.canStayLoggedInOffline();

          if (canStayOffline) {
            // User has valid local session and is within sync window
            try {
              // Try to validate session online (with timeout)
              final isValid = await _authRepository.validateSession();
              if (isValid) {
                // Full authenticated state - online capabilities available
                state = state.copyWith(
                  state: SessionState.authenticated,
                  user: userData,
                  errorMessage: null,
                );
              } else {
                // Session validation failed, but keep offline access
                state = state.copyWith(
                  state: SessionState.authenticatedOffline,
                  user: userData,
                  errorMessage:
                      'Limited offline access - please check your connection',
                );
              }
            } catch (e) {
              // Network error during validation - allow offline access
              log(
                'SessionProvider: Network error during validation, enabling offline mode: $e',
              );
              state = state.copyWith(
                state: SessionState.authenticatedOffline,
                user: userData,
                errorMessage: 'Offline mode - limited functionality available',
              );
            }
          } else {
            // 7-day sync requirement not met - need backend verification
            log(
              'SessionProvider: 7-day sync requirement not met, attempting backend verification',
            );
            try {
              final isValid = await _authRepository.validateSession();
              if (isValid) {
                // Backend verification successful
                state = state.copyWith(
                  state: SessionState.authenticated,
                  user: userData,
                  errorMessage: null,
                );
              } else {
                // Backend verification failed - clear session
                log(
                  'SessionProvider: Backend verification failed, clearing session',
                );
                await _clearSession();
              }
            } catch (e) {
              // Network error during backend verification
              log(
                'SessionProvider: Backend verification failed due to network: $e',
              );
              state = state.copyWith(
                state: SessionState.authenticatedOffline,
                user: userData,
                errorMessage:
                    'Backend sync required - please check your connection',
              );
            }
          }
          return;
        }
      }

      // Check if we need to refresh tokens (only if we have network)
      if (await _authRepository.needsTokenRefresh()) {
        try {
          await _refreshToken();
          return;
        } catch (e) {
          // Token refresh failed - check if we have local user data
          final userData = await _authRepository.getCurrentUser();
          if (userData != null) {
            log('SessionProvider: Token refresh failed, enabling offline mode');
            state = state.copyWith(
              state: SessionState.authenticatedOffline,
              user: userData,
              errorMessage: 'Connection failed - offline mode enabled',
            );
            return;
          }
        }
      }

      // No valid session found
      state = state.copyWith(state: SessionState.unauthenticated);
    } catch (e) {
      // Only clear session if it's a serious error and we have no local data
      final userData = await _authRepository.getCurrentUser();
      if (userData != null) {
        log(
          'SessionProvider: Error during initialization, but user data exists - enabling offline mode',
        );
        state = state.copyWith(
          state: SessionState.authenticatedOffline,
          user: userData,
          errorMessage: 'Error during startup - offline mode enabled',
        );
      } else {
        log(
          'SessionProvider: Error during initialization and no local user data: $e',
        );
        await _clearSession();
      }
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
      // Token refresh failed - check if we have local user data for offline access
      final userData = await _authRepository.getCurrentUser();
      if (userData != null) {
        log('SessionProvider: Token refresh failed, enabling offline mode: $e');
        state = state.copyWith(
          state: SessionState.authenticatedOffline,
          user: userData,
          errorMessage: 'Connection failed - offline mode enabled',
        );
      } else {
        // No local data available, user needs to login again
        log('SessionProvider: Token refresh failed and no local user data: $e');
        await _clearSession();
      }
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

  /// Check if user is authenticated (either online or offline)
  bool get isAuthenticated =>
      state.state == SessionState.authenticated ||
      state.state == SessionState.authenticatedOffline;

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
