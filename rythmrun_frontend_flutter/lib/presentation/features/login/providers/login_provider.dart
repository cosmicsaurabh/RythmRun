import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../domain/entities/login_request_entity.dart';
import '../../../../domain/usecases/login_user_usecase.dart';
import '../models/login_state.dart';

class LoginNotifier extends StateNotifier<LoginState> {
  final LoginUserUsecase _loginUserUsecase;

  LoginNotifier(this._loginUserUsecase)
    : super(const LoginState());

  void updateEmail(String email) {
    state = state.copyWith(email: email, errorMessage: null);
  }

  void updatePassword(String password) {
    state = state.copyWith(
      password: password,
      errorMessage: null,
    );
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
    state = state.copyWith(isLoading: true, errorMessage: null);

    final request = LoginRequestEntity(
      email: state.email.trim().toLowerCase(),
      password: state.password,
    );

    try {
      await _loginUserUsecase(request);
      state = state.copyWith(
        isLoading: false,
        isSuccess: true,
        errorMessage: null,
      );
    } catch (e) {
      // Use centralized error handler for all error formatting
      String errorMessage = ErrorHandler.getErrorMessage(e);
      
      state = state.copyWith(isLoading: false, errorMessage: errorMessage);
    }
  }
}

final loginProvider =
    StateNotifierProvider<LoginNotifier, LoginState>((ref) {
      final loginUserUsecase = ref.watch(loginUserUsecaseProvider);
      return LoginNotifier(loginUserUsecase);
    });
