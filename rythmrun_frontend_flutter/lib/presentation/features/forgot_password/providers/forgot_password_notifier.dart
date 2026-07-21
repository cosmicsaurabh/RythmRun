import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/error_handler.dart';
import '../../../../domain/usecases/request_password_reset_usecase.dart';
import '../models/forgot_password_state.dart';

class ForgotPasswordNotifier extends StateNotifier<ForgotPasswordState> {
  final RequestPasswordResetUsecase _requestPasswordReset;

  ForgotPasswordNotifier(this._requestPasswordReset)
    : super(const ForgotPasswordState());

  void updateEmail(String email) {
    state = state.copyWith(email: email, errorMessage: null);
  }

  bool get _isValidEmail {
    final email = state.email.trim();
    return email.isNotEmpty && email.contains('@') && email.contains('.');
  }

  Future<void> submit() async {
    if (state.isLoading) return;
    if (!_isValidEmail) {
      state = state.copyWith(
        errorMessage: 'Enter the email address for your account.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _requestPasswordReset(state.email.trim().toLowerCase());
      // Generic success regardless of whether the account exists.
      state = state.copyWith(isLoading: false, isSent: true);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ErrorHandler.getErrorMessage(error),
      );
    }
  }
}
