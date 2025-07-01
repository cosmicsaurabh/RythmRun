import '../entities/user_entity.dart';
import '../entities/login_request_entity.dart';
import '../repositories/auth_repository.dart';

class LoginUserUsecase {
  final AuthRepository repository;

  LoginUserUsecase(this.repository);

  Future<UserEntity> call(LoginRequestEntity request) async {
    return await repository.login(request);
  }
}
