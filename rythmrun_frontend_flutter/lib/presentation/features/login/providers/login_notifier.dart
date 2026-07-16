import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/utils/error_handler.dart';
import 'package:rythmrun_frontend_flutter/core/services/google_identity_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_with_google_usecase.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/models/login_state.dart';

class LoginNotifier extends StateNotifier<LoginState> {
  final LoginUserUsecase _loginUserUsecase;
  final LoginWithGoogleUsecase _loginWithGoogleUsecase;
  final GoogleIdentityService _googleIdentityService;
  final int? Function() _beginAuthentication;
  final bool Function(UserEntity user, int admission) _completeAuthentication;

  LoginNotifier(
    this._loginUserUsecase, {
    required LoginWithGoogleUsecase loginWithGoogleUsecase,
    required GoogleIdentityService googleIdentityService,
    required int? Function() beginAuthentication,
    required bool Function(UserEntity user, int admission)
    completeAuthentication,
  }) : _loginWithGoogleUsecase = loginWithGoogleUsecase,
       _googleIdentityService = googleIdentityService,
       _beginAuthentication = beginAuthentication,
       _completeAuthentication = completeAuthentication,
       super(const LoginState());

  void updateEmail(String email) {
    state = state.copyWith(email: email, errorMessage: null);
  }

  void updatePassword(String password) {
    state = state.copyWith(password: password, errorMessage: null);
  }

  void toggleRememberMe(bool rememberMe) {
    state = state.copyWith(rememberMe: rememberMe, errorMessage: null);
  }

  void togglePasswordVisibility() {
    state = state.copyWith(obscurePassword: !state.obscurePassword);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void resetForm() {
    state = const LoginState();
  }

  Future<void> loginUser() async {
    if (state.isLoading) return;

    final admission = _startAuthentication(LoginMethod.password);
    if (admission == null) return;

    final request = LoginRequestEntity(
      email: state.email.trim().toLowerCase(),
      password: state.password,
    );

    try {
      final user = await _loginUserUsecase(request);
      if (!_completeAuthentication(user, admission)) {
        _publishStaleAuthenticationError();
        return;
      }

      _publishSuccess();
    } catch (error) {
      _publishError(error);
    }
  }

  Future<void> loginWithGoogle() async {
    if (state.isLoading) return;

    final admission = _startAuthentication(LoginMethod.google);
    if (admission == null) return;

    try {
      final user = await _loginWithGoogleUsecase();
      if (user == null) {
        // Dismissing Google's account chooser is an intentional outcome, not
        // an authentication failure.
        state = state.copyWith(
          isLoading: false,
          errorMessage: null,
          method: null,
        );
        return;
      }
      if (!_completeAuthentication(user, admission)) {
        await _bestEffortGoogleSignOut();
        _publishStaleAuthenticationError();
        return;
      }

      _publishSuccess();
    } catch (error) {
      _publishError(error);
    }
  }

  int? _startAuthentication(LoginMethod method) {
    final admission = _beginAuthentication();
    if (admission == null) {
      state = state.copyWith(
        isLoading: false,
        method: method,
        errorMessage:
            'Sign out or finish the pending account cleanup before signing in again.',
      );
      return null;
    }

    state = state.copyWith(
      isLoading: true,
      isSuccess: false,
      errorMessage: null,
      method: method,
    );
    return admission;
  }

  void _publishSuccess() {
    state = state.copyWith(
      isLoading: false,
      isSuccess: true,
      errorMessage: null,
    );
  }

  void _publishStaleAuthenticationError() {
    state = state.copyWith(
      isLoading: false,
      errorMessage:
          'The account context changed before sign-in completed. Please retry.',
    );
  }

  void _publishError(Object error) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: ErrorHandler.getErrorMessage(error),
    );
  }

  Future<void> _bestEffortGoogleSignOut() async {
    try {
      await _googleIdentityService.signOut();
    } catch (_) {
      // Preserve the backend/session failure that triggered this cleanup.
    }
  }
}
