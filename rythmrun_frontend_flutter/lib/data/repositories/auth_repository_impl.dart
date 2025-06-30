import '../../domain/entities/user_entity.dart';
import '../../domain/entities/registration_request_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/registration_request_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<UserEntity> registerUser(RegistrationRequestEntity request) async {
    final requestModel = RegistrationRequestModel.fromEntity(request);
    final authResponse = await remoteDataSource.registerUser(requestModel);
    return authResponse.toUserEntity();
  }

  @override
  Future<UserEntity> loginUser(String email, String password) async {
    final authResponse = await remoteDataSource.loginUser(email, password);
    return authResponse.toUserEntity();
  }

  @override
  Future<void> logoutUser() async {
    await remoteDataSource.logoutUser();
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    final userModel = await remoteDataSource.getCurrentUser();
    return userModel?.toEntity();
  }
}
