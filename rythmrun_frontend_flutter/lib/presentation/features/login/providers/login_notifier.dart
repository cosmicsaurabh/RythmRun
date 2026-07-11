import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/utils/error_handler.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/models/login_state.dart';

class LoginNotifier extends StateNotifier<LoginState> {
  final LoginUserUsecase _loginUserUsecase;
  final int? Function() _beginAuthentication;
  final bool Function(UserEntity user, int admission) _completeAuthentication;

  LoginNotifier(
    this._loginUserUsecase, {
    required int? Function() beginAuthentication,
    required bool Function(UserEntity user, int admission)
    completeAuthentication,
  }) : _beginAuthentication = beginAuthentication,
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

    final admission = _beginAuthentication();
    if (admission == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Sign out or finish the pending account cleanup before signing in again.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    final request = LoginRequestEntity(
      email: state.email.trim().toLowerCase(),
      password: state.password,
    );

    try {
      final user = await _loginUserUsecase(request);
      if (!_completeAuthentication(user, admission)) {
        state = state.copyWith(
          isLoading: false,
          errorMessage:
              'The account context changed before sign-in completed. Please retry.',
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isSuccess: true,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ErrorHandler.getErrorMessage(error),
      );
    }
  }
}
