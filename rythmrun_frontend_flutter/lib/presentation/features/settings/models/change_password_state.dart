class ChangePasswordState {
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
    String? errorMessage,
  }) {
    return ChangePasswordState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  ChangePasswordState clearError() {
    return copyWith(errorMessage: null);
  }

  ChangePasswordState reset() {
    return const ChangePasswordState();
  }
}
