import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/auth_failures.dart';
import '../../../../core/utils/error_handler.dart';
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
    } on AuthSessionFailure catch (e) {
      // A dead/expired session surfaces its curated message; the coordinator has
      // already emitted the invalidation signal that drives the global logout.
      state = state.copyWith(
        isLoading: false,
        errorMessage: ErrorHandler.getErrorMessage(e),
      );
      return null;
    } catch (e) {
      // Stable backend codes (e.g. AUTH_PASSWORD_INVALID) render curated text via
      // ErrorHandler — never a raw toString() with the class name welded on.
      state = state.copyWith(
        isLoading: false,
        errorMessage: ErrorHandler.getErrorMessage(e),
      );
      return null;
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
