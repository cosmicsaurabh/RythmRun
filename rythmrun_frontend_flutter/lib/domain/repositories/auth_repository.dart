import '../entities/user_entity.dart';
import '../entities/registration_request_entity.dart';

abstract class AuthRepository {
  Future<UserEntity> registerUser(RegistrationRequestEntity request);
  Future<UserEntity> loginUser(String email, String password);
  Future<void> logoutUser();
  Future<UserEntity?> getCurrentUser();
}
