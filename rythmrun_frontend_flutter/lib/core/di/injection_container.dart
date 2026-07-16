import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/services/activity_image_file_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_persistence_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_token_store.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/core/services/google_identity_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
import 'package:rythmrun_frontend_flutter/core/services/sync_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/services/session_invalidation_signal.dart';
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
import '../../domain/usecases/login_with_google_usecase.dart';
import '../../domain/usecases/register_user_usecase.dart';
import '../../domain/usecases/change_password_usecase.dart';

// HTTP Client Provider
final httpClientProvider = Provider<AppHttpClient>((ref) {
  final client = AppHttpClient();
  ref.onDispose(client.close);
  return client;
});

final authTokenStoreProvider = Provider<AuthTokenStore>((ref) {
  return SecureAuthTokenStore();
});

final authPersistenceServiceProvider = Provider<AuthPersistenceService>((ref) {
  return AuthPersistenceService(tokenStore: ref.watch(authTokenStoreProvider));
});

final googleIdentityServiceProvider = Provider<GoogleIdentityService>((ref) {
  return NativeGoogleIdentityService(
    clientId: AppConfig.googleClientId,
    serverClientId: AppConfig.googleServerClientId,
    backendUsesSecureTransport: AppConfig.googleAuthUsesSecureTransport,
    clientIdRequired: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
  );
});

// Data Sources
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final httpClient = ref.watch(httpClientProvider);
  return AuthRemoteDataSource(httpClient: httpClient);
});

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSource(
    persistenceService: ref.watch(authPersistenceServiceProvider),
  );
});

final _localDbServiceProvider = Provider<LocalDbService>((ref) {
  return LocalDbService();
});

final userScopeOperationGateProvider = Provider<UserScopeOperationGate>((ref) {
  return UserScopeOperationGate();
});

final onlineOperationGuardProvider = Provider<OnlineOperationGuard>((ref) {
  return OnlineOperationGuard();
});

final authenticationAttemptGateProvider = Provider<AuthenticationAttemptGate>((
  ref,
) {
  return AuthenticationAttemptGate();
});

final sessionInvalidationSignalProvider = Provider<SessionInvalidationSignal>((
  ref,
) {
  final signal = SessionInvalidationSignal();
  ref.onDispose(signal.dispose);
  return signal;
});

final authenticatedRequestCoordinatorProvider =
    Provider<AuthenticatedRequestCoordinator>((ref) {
      final local = ref.watch(authLocalDataSourceProvider);
      return AuthenticatedRequestCoordinator(
        credentialVault: local,
        rejectedCredentialQuarantine: local,
        authRemoteDataSource: ref.watch(authRemoteDataSourceProvider),
        authenticationAttemptGate: ref.watch(authenticationAttemptGateProvider),
        sessionInvalidationSignal: ref.watch(sessionInvalidationSignalProvider),
        commitRefreshedSession: (response) async {
          await local.updateUserData(response.toUserEntity());
          await local.updateLastBackendSync();
        },
        commitServerVerification: local.updateLastBackendSync,
      );
    });

final activityImageFileServiceProvider = Provider<ActivityImageFileService>((
  ref,
) {
  return ActivityImageFileService();
});

final workoutLocalDataSourceProvider = Provider<WorkoutLocalDataSource>((ref) {
  final localDbService = ref.watch(_localDbServiceProvider);
  return WorkoutLocalDataSource(localDbService);
});

final activityImageLocalDataSourceProvider =
    Provider<ActivityImageLocalDataSource>((ref) {
      final localDbService = ref.watch(_localDbServiceProvider);
      return ActivityImageLocalDataSource(localDbService);
    });

final activityImageRemoteDataSourceProvider =
    Provider<ActivityImageRemoteDataSource>((ref) {
      final httpClient = ref.watch(httpClientProvider);
      return ActivityImageRemoteDataSource(
        httpClient: httpClient,
        authenticatedRequests: ref.watch(
          authenticatedRequestCoordinatorProvider,
        ),
      );
    });

final avatarRemoteDataSourceProvider = Provider<AvatarRemoteDataSource>((ref) {
  final httpClient = ref.watch(httpClientProvider);
  return AvatarRemoteDataSourceImpl(
    httpClient,
    ref.watch(authenticatedRequestCoordinatorProvider),
  );
});

final activityRemoteDataSourceProvider = Provider<ActivityRemoteDataSource>((
  ref,
) {
  final httpClient = ref.watch(httpClientProvider);
  return ActivityRemoteDataSource(
    httpClient: httpClient,
    authenticatedRequests: ref.watch(authenticatedRequestCoordinatorProvider),
  );
});

// Repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final localDataSource = ref.watch(authLocalDataSourceProvider);
  return AuthRepositoryImpl(
    remoteDataSource,
    localDataSource,
    authenticatedRequests: ref.watch(authenticatedRequestCoordinatorProvider),
    authenticationAttemptGate: ref.watch(authenticationAttemptGateProvider),
    onlineOperationGuard: ref.watch(onlineOperationGuardProvider),
    googleIdentityService: ref.watch(googleIdentityServiceProvider),
  );
});

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  final remoteDataSource = ref.watch(avatarRemoteDataSourceProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  final httpClient = ref.watch(httpClientProvider);
  return AvatarRepositoryImpl(
    remoteDataSource,
    authRepository,
    httpClient,
    operationGate: ref.watch(userScopeOperationGateProvider),
    onlineOperationGuard: ref.watch(onlineOperationGuardProvider),
  );
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final localDataSource = ref.watch(workoutLocalDataSourceProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  final activityRemoteDataSource = ref.watch(activityRemoteDataSourceProvider);
  return WorkoutRepositoryImpl(
    localDataSource,
    authRepository,
    activityRemoteDataSource,
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
    workoutLocalDataSource: ref.watch(workoutLocalDataSourceProvider),
    operationGate: ref.watch(userScopeOperationGateProvider),
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator(
    workoutRepository: ref.watch(workoutRepositoryProvider),
    activityImageRepository: ref.watch(activityImageRepositoryProvider),
    authRepository: ref.watch(authRepositoryProvider),
    operationGate: ref.watch(userScopeOperationGateProvider),
    onlineOperationGuard: ref.watch(onlineOperationGuardProvider),
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

final loginWithGoogleUsecaseProvider = Provider<LoginWithGoogleUsecase>((ref) {
  return LoginWithGoogleUsecase(ref.watch(authRepositoryProvider));
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
