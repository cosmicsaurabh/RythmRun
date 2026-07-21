import 'package:flutter/foundation.dart';

@immutable
class ForgotPasswordState {
  static const Object _unset = Object();

  final String email;
  final bool isLoading;

  /// True once a request has been accepted by the server. Because the backend
  /// is anti-enumerating, this only means "we asked" — never "the account
  /// exists".
  final bool isSent;
  final String? errorMessage;

  const ForgotPasswordState({
    this.email = '',
    this.isLoading = false,
    this.isSent = false,
    this.errorMessage,
  });

  ForgotPasswordState copyWith({
    String? email,
    bool? isLoading,
    bool? isSent,
    Object? errorMessage = _unset,
  }) {
    return ForgotPasswordState(
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
      isSent: isSent ?? this.isSent,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgotPasswordState &&
          runtimeType == other.runtimeType &&
          email == other.email &&
          isLoading == other.isLoading &&
          isSent == other.isSent &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(email, isLoading, isSent, errorMessage);

  @override
  String toString() {
    return 'ForgotPasswordState{isLoading: $isLoading, isSent: $isSent, errorMessage: $errorMessage}';
  }
}
