import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../domain/usecases/change_password_usecase.dart';
import '../models/change_password_state.dart';

class ChangePasswordNotifier extends StateNotifier<ChangePasswordState> {
  final ChangePasswordUsecase _changePasswordUsecase;

  ChangePasswordNotifier(this._changePasswordUsecase)
    : super(ChangePasswordState.initial());

  Future<String?> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _changePasswordUsecase(
        currentPassword,
        newPassword,
      );
      state = state.copyWith(isLoading: false, isSuccess: true);
      return response.message; // Return success message
    } catch (e) {
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: errorMessage);
      return null; // Return null on error
    }
  }

  void clearError() {
    state = state.clearError();
  }

  void reset() {
    state = state.reset();
  }
}

final changePasswordProvider =
    StateNotifierProvider<ChangePasswordNotifier, ChangePasswordState>((ref) {
      final usecase = ref.watch(changePasswordUsecaseProvider);
      return ChangePasswordNotifier(usecase);
    });
