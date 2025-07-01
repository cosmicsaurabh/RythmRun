import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/http_client.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/datasources/auth_local_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/usecases/login_user_usecase.dart';
import '../../domain/usecases/register_user_usecase.dart';

// HTTP Client Provider
final httpClientProvider = Provider<AppHttpClient>((ref) {
  return AppHttpClient();
});

// Data Sources
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final httpClient = ref.watch(httpClientProvider);
  return AuthRemoteDataSource(httpClient: httpClient);
});

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSource();
});

// Repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final localDataSource = ref.watch(authLocalDataSourceProvider);
  return AuthRepositoryImpl(remoteDataSource, localDataSource);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl();
});

// Use Cases
final loginUserUsecaseProvider = Provider<LoginUserUsecase>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return LoginUserUsecase(repository);
});

final registerUserUsecaseProvider = Provider<RegisterUserUsecase>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return RegisterUserUsecase(repository);
});
