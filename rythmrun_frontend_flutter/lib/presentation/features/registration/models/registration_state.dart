
import 'package:flutter/foundation.dart';
import '../../../../core/utils/validation_helper.dart';

@immutable
class RegistrationState {
  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final String confirmPassword;
  final bool acceptedTerms;
  final bool isLoading;
  final String? errorMessage;
  final bool isSuccess;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final PasswordStrength passwordStrength;

  const RegistrationState({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.password = '',
    this.confirmPassword = '',
    this.acceptedTerms = false,
    this.isLoading = false,
    this.errorMessage,
    this.isSuccess = false,
    this.obscurePassword = true,
    this.obscureConfirmPassword = true,
    this.passwordStrength = PasswordStrength.weak,
  });

  RegistrationState copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? password,
    String? confirmPassword,
    bool? acceptedTerms,
    bool? isLoading,
    String? errorMessage,
    bool? isSuccess,
    bool? obscurePassword,
    bool? obscureConfirmPassword,
    PasswordStrength? passwordStrength,
  }) {
    return RegistrationState(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      acceptedTerms: acceptedTerms ?? this.acceptedTerms,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      isSuccess: isSuccess ?? this.isSuccess,
      obscurePassword: obscurePassword ?? this.obscurePassword,
      obscureConfirmPassword:
          obscureConfirmPassword ?? this.obscureConfirmPassword,
      passwordStrength: passwordStrength ?? this.passwordStrength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegistrationState &&
          runtimeType == other.runtimeType &&
          firstName == other.firstName &&
          lastName == other.lastName &&
          email == other.email &&
          password == other.password &&
          confirmPassword == other.confirmPassword &&
          acceptedTerms == other.acceptedTerms &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage &&
          isSuccess == other.isSuccess &&
          obscurePassword == other.obscurePassword &&
          obscureConfirmPassword == other.obscureConfirmPassword &&
          passwordStrength == other.passwordStrength;

  
  @override
  String toString() {
    return 'RegistrationState{firstName: $firstName, lastName: $lastName, email: $email, acceptedTerms: $acceptedTerms, isLoading: $isLoading, errorMessage: $errorMessage, isSuccess: $isSuccess, passwordStrength: $passwordStrength}';
  }
}
