import '../repositories/auth_repository.dart';

class RequestPasswordResetUsecase {
  final AuthRepository repository;

  RequestPasswordResetUsecase(this.repository);

  Future<void> call(String email) async {
    return await repository.requestPasswordReset(email);
  }
}
