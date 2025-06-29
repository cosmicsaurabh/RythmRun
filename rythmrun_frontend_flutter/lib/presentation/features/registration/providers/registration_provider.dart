import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/utils/validation_helper.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../domain/entities/registration_request_entity.dart';
import '../../../../domain/usecases/register_user_usecase.dart';
import '../models/registration_state.dart';

class RegistrationNotifier extends StateNotifier<RegistrationState> {
  final RegisterUserUsecase _registerUserUsecase;

  RegistrationNotifier(this._registerUserUsecase)
    : super(const RegistrationState());

  void updateFirstName(String firstName) {
    state = state.copyWith(firstName: firstName, errorMessage: null);
  }

  void updateLastName(String lastName) {
    state = state.copyWith(lastName: lastName, errorMessage: null);
  }

  void updateEmail(String email) {
    state = state.copyWith(email: email, errorMessage: null);
  }

  void updatePassword(String password) {
    final passwordStrength = ValidationHelper.getPasswordStrength(password);
    state = state.copyWith(
      password: password,
      passwordStrength: passwordStrength,
      errorMessage: null,
    );
  }

  void updateConfirmPassword(String confirmPassword) {
    state = state.copyWith(
      confirmPassword: confirmPassword,
      errorMessage: null,
    );
  }

  void toggleAcceptedTerms(bool accepted) {
    state = state.copyWith(acceptedTerms: accepted, errorMessage: null);
  }

  void togglePasswordVisibility() {
    state = state.copyWith(obscurePassword: !state.obscurePassword);
  }

  void toggleConfirmPasswordVisibility() {
    state = state.copyWith(
      obscureConfirmPassword: !state.obscureConfirmPassword,
    );
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void resetForm() {
    state = const RegistrationState();
  }

  Future<void> registerUser() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final request = RegistrationRequestEntity(
      firstName: state.firstName.trim(),
      lastName: state.lastName.trim(),
      email: state.email.trim().toLowerCase(),
      password: state.password,
      acceptedTerms: state.acceptedTerms,
    );

    try {
      await _registerUserUsecase(request);
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

final registrationProvider =
    StateNotifierProvider<RegistrationNotifier, RegistrationState>((ref) {
      final registerUserUsecase = ref.watch(registerUserUsecaseProvider);
      return RegistrationNotifier(registerUserUsecase);
    });
