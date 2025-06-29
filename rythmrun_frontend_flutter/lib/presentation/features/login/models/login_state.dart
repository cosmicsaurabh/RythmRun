import 'package:flutter/foundation.dart';

@immutable
class LoginState {
  final String email;
  final String password;
  final bool rememberMe;
  final bool isLoading;
  final String? errorMessage;
  final bool isSuccess;
  final bool obscurePassword;

  const LoginState({
    this.email = '',
    this.password = '',
    this.rememberMe = false,
    this.isLoading = false,
    this.errorMessage,
    this.isSuccess = false,
    this.obscurePassword = true,
  });

  LoginState copyWith({
    String? email,
    String? password,
    bool? rememberMe,
    bool? isLoading,
    String? errorMessage,
    bool? isSuccess,
    bool? obscurePassword,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      rememberMe: rememberMe ?? this.rememberMe,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      isSuccess: isSuccess ?? this.isSuccess,
      obscurePassword: obscurePassword ?? this.obscurePassword,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginState &&
          runtimeType == other.runtimeType &&
          email == other.email &&
          password == other.password &&
          rememberMe == other.rememberMe &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage &&
          isSuccess == other.isSuccess &&
          obscurePassword == other.obscurePassword;


  @override
  String toString() {
    return 'LoginState{email: $email, rememberMe: $rememberMe, isLoading: $isLoading, errorMessage: $errorMessage, isSuccess: $isSuccess}';
  }
} 