import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';

import '../repositories/auth_repository.dart';

class ChangePasswordUsecase {
  final AuthRepository authRepository;

  ChangePasswordUsecase(this.authRepository);

  Future<ChangePasswordResponseModel> call(
    String currentPassword,
    String newPassword,
  ) async {
    // Validate passwords
    if (currentPassword.isEmpty) {
      throw Exception('Current password cannot be empty');
    }

    if (newPassword.isEmpty) {
      throw Exception('New password cannot be empty');
    }

    if (newPassword.length < 8) {
      throw Exception('New password must be at least 8 characters long');
    }

    if (currentPassword == newPassword) {
      throw Exception('New password must be different from current password');
    }

    return await authRepository.changePassword(currentPassword, newPassword);
  }
}
