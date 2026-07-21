import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/data/models/change_password_response_model.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/registration_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/change_password_usecase.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/register_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/providers/registration_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/settings/providers/change_password_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/activity_images_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_details_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';

void main() {
  group('nullable state transitions', () {
    test('successful registration retry clears the previous error', () async {
      final repository = _FakeAuthRepository(registrationFailuresRemaining: 1);
      final registeredUsers = <UserEntity>[];
      final notifier = RegistrationNotifier(
        RegisterUserUsecase(repository),
        completeAuthentication: (user, _) {
          registeredUsers.add(user);
          return true;
        },
      );
      addTearDown(notifier.dispose);

      await notifier.registerUser();
      expect(notifier.state.errorMessage, isNotNull);

      await notifier.registerUser();
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isSuccess, isTrue);
      expect(registeredUsers, <UserEntity>[_FakeAuthRepository.user]);
    });

    test(
      'authenticated session blocks registration before the request',
      () async {
        final repository = _FakeAuthRepository();
        final notifier = RegistrationNotifier(
          RegisterUserUsecase(repository),
          beginAuthentication: () => null,
          completeAuthentication:
              (_, _) => fail('registration success must not be reported'),
        );
        addTearDown(notifier.dispose);

        await notifier.registerUser();

        expect(repository.registrationCalls, 0);
        expect(notifier.state.isLoading, isFalse);
        expect(notifier.state.errorMessage, contains('Sign out'));
      },
    );

    test('successful password retry clears the previous error', () async {
      final repository = _FakeAuthRepository(passwordFailuresRemaining: 1);
      final notifier = ChangePasswordNotifier(
        ChangePasswordUsecase(repository),
      );
      addTearDown(notifier.dispose);

      await notifier.changePassword('old-password', 'new-password');
      expect(notifier.state.errorMessage, isNotNull);

      await notifier.changePassword('old-password', 'new-password');
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isSuccess, isTrue);
    });

    test('details retry clears the old workout and previous error', () async {
      final repository = _FakeWorkoutRepository(
        workoutResult: _workout('first'),
      );
      final notifier = TrackingHistoryDetailsNotifier(
        repository,
        expectedUserId: 7,
      );
      addTearDown(notifier.dispose);

      await notifier.loadWorkoutDetails('1');
      expect(notifier.state.workout?.id, 'first');

      repository.failWorkoutLoads = true;
      await notifier.loadWorkoutDetails('2');
      expect(notifier.state.workout, isNull);
      expect(notifier.state.errorMessage, isNotNull);

      repository
        ..failWorkoutLoads = false
        ..workoutResult = _workout('second');
      await notifier.loadWorkoutDetails('2');
      expect(notifier.state.workout?.id, 'second');
      expect(notifier.state.errorMessage, isNull);
    });

    test('details reject a workout returned for another owner', () async {
      final repository = _FakeWorkoutRepository(
        workoutResult: _workout('other-owner', userId: 8),
      );
      final notifier = TrackingHistoryDetailsNotifier(
        repository,
        expectedUserId: 7,
      );
      addTearDown(notifier.dispose);

      await notifier.loadWorkoutDetails('1');

      expect(notifier.state.workout, isNull);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, contains('this account'));
    });

    test('history refresh discards and reloads cached overall stats', () async {
      final repository = _FakeWorkoutRepository();
      final notifier = TrackingHistoryNotifier(repository);
      addTearDown(notifier.dispose);

      await notifier.loadInitialData();
      expect(repository.statisticsCalls, 2);
      expect(notifier.state.overallStatistics?.totalWorkouts, 1);

      await notifier.refresh();
      expect(repository.statisticsCalls, 4);
      expect(notifier.state.overallStatistics?.totalWorkouts, 3);
    });

    test('successful image reload clears the previous error', () async {
      final repository = _FakeActivityImageRepository(failLoads: true);
      final notifier = ActivityImagesNotifier(
        repository: repository,
        workoutId: 42,
        expectedUserId: 7,
      );
      addTearDown(notifier.dispose);

      await notifier.load();
      expect(notifier.state.errorMessage, isNotNull);

      repository.failLoads = false;
      await notifier.load();
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.images, isEmpty);
    });

    test('image load cannot write state after notifier disposal', () async {
      final repository = _FakeActivityImageRepository(failLoads: false);
      final loadCompleter = Completer<List<ActivityImageEntity>>();
      repository.loadCompleter = loadCompleter;
      final notifier = ActivityImagesNotifier(
        repository: repository,
        workoutId: 42,
        expectedUserId: 7,
      );

      final pendingLoad = notifier.load();
      notifier.dispose();
      loadCompleter.complete(const []);

      await expectLater(pendingLoad, completes);
      await expectLater(notifier.load(), completes);
    });

    test(
      'image load drops a result after the expected owner changes',
      () async {
        final repository = _FakeActivityImageRepository(failLoads: false);
        final loadCompleter = Completer<List<ActivityImageEntity>>();
        repository.loadCompleter = loadCompleter;
        var isExpectedOwnerActive = true;
        final notifier = ActivityImagesNotifier(
          repository: repository,
          workoutId: 42,
          expectedUserId: 7,
          isExpectedOwnerActive: (_) => isExpectedOwnerActive,
        );
        addTearDown(notifier.dispose);

        final pendingLoad = notifier.load();
        isExpectedOwnerActive = false;
        loadCompleter.complete(<ActivityImageEntity>[_image(workoutId: 42)]);
        await pendingLoad;

        expect(notifier.state.images, isEmpty);
        expect(notifier.state.isLoading, isFalse);
        expect(notifier.state.errorMessage, contains('this account'));
      },
    );

    test('image load rejects rows returned for another workout', () async {
      final repository = _FakeActivityImageRepository(
        failLoads: false,
        loadResult: <ActivityImageEntity>[_image(workoutId: 99)],
      );
      final notifier = ActivityImagesNotifier(
        repository: repository,
        workoutId: 42,
        expectedUserId: 7,
      );
      addTearDown(notifier.dispose);

      await notifier.load();

      expect(notifier.state.images, isEmpty);
      expect(notifier.state.errorMessage, contains('invalid owner scope'));
    });
  });
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<UserEntity> refreshCurrentUser() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

  _FakeAuthRepository({
    this.registrationFailuresRemaining = 0,
    this.passwordFailuresRemaining = 0,
  });

  int registrationFailuresRemaining;
  int passwordFailuresRemaining;
  int registrationCalls = 0;

  static const user = UserEntity(
    id: '7',
    firstName: 'A',
    lastName: 'Runner',
    email: 'runner@example.com',
  );

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) async {
    registrationCalls += 1;
    if (registrationFailuresRemaining > 0) {
      registrationFailuresRemaining -= 1;
      throw StateError('simulated registration failure');
    }
    return user;
  }

  @override
  Future<ChangePasswordResponseModel> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (passwordFailuresRemaining > 0) {
      passwordFailuresRemaining -= 1;
      throw StateError('simulated password failure');
    }
    return const ChangePasswordResponseModel(message: 'changed', success: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWorkoutRepository implements WorkoutRepository {
  _FakeWorkoutRepository({this.workoutResult});

  WorkoutSessionEntity? workoutResult;
  bool failWorkoutLoads = false;
  int statisticsCalls = 0;

  @override
  Future<WorkoutSessionEntity?> getWorkout(int workoutId) async {
    if (failWorkoutLoads) {
      throw StateError('simulated details failure');
    }
    return workoutResult;
  }

  @override
  Future<PaginatedWorkouts> getPaginatedWorkouts({
    int page = 1,
    int limit = 20,
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    bool loadTrackingPoints = false,
  }) async {
    return PaginatedWorkouts(
      workouts: const [],
      currentPage: page,
      totalPages: 1,
      totalCount: 0,
      hasNextPage: false,
      hasPreviousPage: false,
      limit: limit,
    );
  }

  @override
  Future<WorkoutStatistics> getWorkoutStatistics({
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    statisticsCalls += 1;
    return _statistics(statisticsCalls);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeActivityImageRepository implements ActivityImageRepository {
  _FakeActivityImageRepository({
    required this.failLoads,
    this.loadResult = const <ActivityImageEntity>[],
  });

  bool failLoads;
  List<ActivityImageEntity> loadResult;
  Completer<List<ActivityImageEntity>>? loadCompleter;

  @override
  Future<List<ActivityImageEntity>> getImagesForWorkout(
    int localWorkoutId,
  ) async {
    final pendingLoad = loadCompleter;
    if (pendingLoad != null) {
      return pendingLoad.future;
    }
    if (failLoads) {
      throw StateError('simulated image load failure');
    }
    return loadResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WorkoutSessionEntity _workout(String id, {int userId = 7}) {
  return WorkoutSessionEntity(
    id: id,
    clientSyncId: 'client-$id',
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    userId: userId,
  );
}

ActivityImageEntity _image({required int workoutId}) {
  final now = DateTime.utc(2026, 7, 11);
  return ActivityImageEntity(
    localId: workoutId,
    localWorkoutId: workoutId,
    clientImageId: 'image-$workoutId',
    localPath: '/synthetic/image-$workoutId.jpg',
    contentType: 'image/jpeg',
    sizeBytes: 10,
    status: ActivityImageSyncStatus.queued,
    createdAt: now,
    updatedAt: now,
  );
}

WorkoutStatistics _statistics(int totalWorkouts) {
  return WorkoutStatistics(
    totalWorkouts: totalWorkouts,
    totalDistance: totalWorkouts * 1000,
    averageDistance: 1000,
    totalCalories: totalWorkouts * 100,
    averageCalories: 100,
    maxDistance: 1000,
    totalDuration: Duration(minutes: totalWorkouts * 10),
    averageDuration: const Duration(minutes: 10),
  );
}
