import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/services/activity_image_file_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/sync_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_image_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_image_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/avatar_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/activity_image_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/avatar_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/live_tracking_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
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

final userScopeOperationGateProvider = Provider<UserScopeOperationGate>((ref) {
  return UserScopeOperationGate();
});

final authenticationAttemptGateProvider = Provider<AuthenticationAttemptGate>((
  ref,
) {
  return AuthenticationAttemptGate();
});

final activityImageFileServiceProvider = Provider<ActivityImageFileService>((
  ref,
) {
  return ActivityImageFileService();
});

final workoutLocalDataSourceProvider = Provider<WorkoutLocalDataSource>((ref) {
  final localDbService = ref.watch(localDbServiceProvider);
  return WorkoutLocalDataSource(localDbService);
});

final activityImageLocalDataSourceProvider =
    Provider<ActivityImageLocalDataSource>((ref) {
      final localDbService = ref.watch(localDbServiceProvider);
      return ActivityImageLocalDataSource(localDbService);
    });

final activityImageRemoteDataSourceProvider =
    Provider<ActivityImageRemoteDataSource>((ref) {
      final httpClient = ref.watch(httpClientProvider);
      return ActivityImageRemoteDataSource(httpClient: httpClient);
    });

final avatarRemoteDataSourceProvider = Provider<AvatarRemoteDataSource>((ref) {
  final httpClient = ref.watch(httpClientProvider);
  return AvatarRemoteDataSourceImpl(httpClient);
});

final activityRemoteDataSourceProvider = Provider<ActivityRemoteDataSource>((
  ref,
) {
  final httpClient = ref.watch(httpClientProvider);
  return ActivityRemoteDataSource(httpClient: httpClient);
});

// Repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final localDataSource = ref.watch(authLocalDataSourceProvider);
  return AuthRepositoryImpl(
    remoteDataSource,
    localDataSource,
    authenticationAttemptGate: ref.watch(authenticationAttemptGateProvider),
  );
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
  final activityRemoteDataSource = ref.watch(activityRemoteDataSourceProvider);
  final authLocalDataSource = ref.watch(authLocalDataSourceProvider);
  return WorkoutRepositoryImpl(
    localDataSource,
    authRepository,
    activityRemoteDataSource,
    authLocalDataSource,
    operationGate: ref.watch(userScopeOperationGateProvider),
  );
});

final activityImageRepositoryProvider = Provider<ActivityImageRepository>((
  ref,
) {
  return ActivityImageRepositoryImpl(
    localDataSource: ref.watch(activityImageLocalDataSourceProvider),
    remoteDataSource: ref.watch(activityImageRemoteDataSourceProvider),
    fileService: ref.watch(activityImageFileServiceProvider),
    authRepository: ref.watch(authRepositoryProvider),
    authLocalDataSource: ref.watch(authLocalDataSourceProvider),
    workoutLocalDataSource: ref.watch(workoutLocalDataSourceProvider),
    operationGate: ref.watch(userScopeOperationGateProvider),
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator(
    ref.watch(workoutRepositoryProvider),
    ref.watch(activityImageRepositoryProvider),
  );
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
