import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/avatar_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/avatar_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/live_tracking_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';
import '../network/http_client.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/datasources/auth_local_datasource.dart';
import '../../data/datasources/workout_local_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/workout_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/workout_repository.dart';
import '../../domain/usecases/login_user_usecase.dart';
import '../../domain/usecases/register_user_usecase.dart';
import '../../domain/usecases/change_password_usecase.dart';

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

final localDbServiceProvider = Provider<LocalDbService>((ref) {
  return LocalDbService();
});

final workoutLocalDataSourceProvider = Provider<WorkoutLocalDataSource>((ref) {
  final localDbService = ref.watch(localDbServiceProvider);
  return WorkoutLocalDataSource(localDbService);
});

final avatarRemoteDataSourceProvider = Provider<AvatarRemoteDataSource>((ref) {
  final httpClient = ref.watch(httpClientProvider);
  return AvatarRemoteDataSourceImpl(httpClient);
});

// Repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final localDataSource = ref.watch(authLocalDataSourceProvider);
  return AuthRepositoryImpl(remoteDataSource, localDataSource);
});

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  final remoteDataSource = ref.watch(avatarRemoteDataSourceProvider);
  final localDataSource = ref.watch(authLocalDataSourceProvider);
  final httpClient = ref.watch(httpClientProvider);
  return AvatarRepositoryImpl(remoteDataSource, localDataSource, httpClient);
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final localDataSource = ref.watch(workoutLocalDataSourceProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  return WorkoutRepositoryImpl(localDataSource, authRepository);
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

final changePasswordUsecaseProvider = Provider<ChangePasswordUsecase>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return ChangePasswordUsecase(repository);
});

final liveTrackingRepositoryProvider = Provider<LiveTrackingRepository>((ref) {
  return LiveTrackingRepositoryImpl();
});
