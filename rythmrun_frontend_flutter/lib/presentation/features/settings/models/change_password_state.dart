class ChangePasswordState {
  static const Object _unset = Object();

  final bool isLoading;
  final bool isSuccess;
  final String? errorMessage;

  const ChangePasswordState({
    this.isLoading = false,
    this.isSuccess = false,
    this.errorMessage,
  });

  factory ChangePasswordState.initial() {
    return const ChangePasswordState();
  }

  ChangePasswordState copyWith({
    bool? isLoading,
    bool? isSuccess,
    Object? errorMessage = _unset,
  }) {
    return ChangePasswordState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
    );
  }

  ChangePasswordState clearError() {
    return copyWith(errorMessage: null);
  }

  ChangePasswordState reset() {
    return const ChangePasswordState();
  }
}
