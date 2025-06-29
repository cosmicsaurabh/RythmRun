import '../entities/user_entity.dart';
import '../entities/registration_request_entity.dart';
import '../repositories/auth_repository.dart';

class RegisterUserUsecase {
  final AuthRepository authRepository;

  RegisterUserUsecase(this.authRepository);

  Future<UserEntity> call(RegistrationRequestEntity request) async {
    // Simply call register - backend will handle email existence check
    return await authRepository.registerUser(request);
  }
}
