import 'package:flutter/foundation.dart';

enum LoginMethod { password, google }

@immutable
class LoginState {
  static const Object _unset = Object();

  final String email;
  final String password;
  final bool rememberMe;
  final bool isLoading;
  final String? errorMessage;
  final bool isSuccess;
  final bool obscurePassword;
  final LoginMethod? method;

  const LoginState({
    this.email = '',
    this.password = '',
    this.rememberMe = false,
    this.isLoading = false,
    this.errorMessage,
    this.isSuccess = false,
    this.obscurePassword = true,
    this.method,
  });

  LoginState copyWith({
    String? email,
    String? password,
    bool? rememberMe,
    bool? isLoading,
    Object? errorMessage = _unset,
    bool? isSuccess,
    bool? obscurePassword,
    Object? method = _unset,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      rememberMe: rememberMe ?? this.rememberMe,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
      isSuccess: isSuccess ?? this.isSuccess,
      obscurePassword: obscurePassword ?? this.obscurePassword,
      method: identical(method, _unset) ? this.method : method as LoginMethod?,
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
          obscurePassword == other.obscurePassword &&
          method == other.method;

  @override
  int get hashCode => Object.hash(
    email,
    password,
    rememberMe,
    isLoading,
    errorMessage,
    isSuccess,
    obscurePassword,
    method,
  );

  @override
  String toString() {
    return 'LoginState{email: $email, rememberMe: $rememberMe, isLoading: $isLoading, errorMessage: $errorMessage, isSuccess: $isSuccess, method: $method}';
  }
}
