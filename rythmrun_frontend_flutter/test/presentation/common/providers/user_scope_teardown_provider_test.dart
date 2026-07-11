import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/live_tracking_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/workout_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/user_scope_teardown_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/providers/calculator_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/home/screens/home_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/profile/providers/profile_view_model.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/settings/providers/change_password_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/activity_images_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_details_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';

void main() {
  test('A cache is invalidated again before activating B', () async {
    final workoutRepository = _ScopedWorkoutRepository(currentUserId: 7);
    final imageRepository = _ScopedImageRepository(workoutRepository);
    final container = ProviderContainer(
      overrides: <Override>[
        workoutRepositoryProvider.overrideWithValue(workoutRepository),
        activityImageRepositoryProvider.overrideWithValue(imageRepository),
        avatarRepositoryProvider.overrideWithValue(_FakeAvatarRepository()),
        liveTrackingRepositoryProvider.overrideWithValue(
          _FakeLiveTrackingRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final coordinator = container.read(userScopeTeardownProvider);

    coordinator.activateUserScope('7');
    final historySubscription = container.listen(
      trackingHistoryProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(historySubscription.close);
    final detailsSubscriptionA = container.listen(
      trackingHistoryDetailsProvider((userId: 7, workoutId: 7)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(detailsSubscriptionA.close);
    final imagesSubscriptionA = container.listen(
      activityImagesProvider((userId: 7, workoutId: 7)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(imagesSubscriptionA.close);

    final liveNotifierA = container.read(liveTrackingProvider.notifier);
    final profileNotifierA = container.read(profileViewModelProvider.notifier);
    final calculatorNotifierA = container.read(calculatorProvider.notifier);
    final passwordNotifierA = container.read(changePasswordProvider.notifier);
    final syncCoordinatorA = container.read(syncCoordinatorProvider);
    container.read(tabIndexProvider.notifier).state = 3;
    calculatorNotifierA.updateData(age: 31);

    await _flushAsyncWork();
    expect(container.read(trackingHistoryProvider).workouts.single.userId, 7);
    expect(
      container
          .read(trackingHistoryDetailsProvider((userId: 7, workoutId: 7)))
          .workout
          ?.userId,
      7,
    );
    expect(
      container
          .read(activityImagesProvider((userId: 7, workoutId: 7)))
          .images
          .single
          .clientImageId,
      'image-7',
    );

    final teardown = await coordinator.teardown(
      reason: UserScopeExitReason.voluntaryLogout,
    );
    expect(teardown.isCompleted, isTrue);

    workoutRepository.currentUserId = 8;
    coordinator.activateUserScope('8');
    final detailsSubscriptionB = container.listen(
      trackingHistoryDetailsProvider((userId: 8, workoutId: 8)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(detailsSubscriptionB.close);
    final imagesSubscriptionB = container.listen(
      activityImagesProvider((userId: 8, workoutId: 8)),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(imagesSubscriptionB.close);
    await _flushAsyncWork();

    final stateForB = container.read(trackingHistoryProvider);
    expect(stateForB.workouts, hasLength(1));
    expect(stateForB.workouts.single.userId, 8);
    expect(workoutRepository.loadedUserIds.last, 8);
    expect(
      container
          .read(trackingHistoryDetailsProvider((userId: 8, workoutId: 8)))
          .workout
          ?.userId,
      8,
    );
    expect(
      container
          .read(activityImagesProvider((userId: 8, workoutId: 8)))
          .images
          .single
          .clientImageId,
      'image-8',
    );
    expect(container.read(tabIndexProvider), 0);
    expect(container.read(calculatorProvider).age, isNull);
    expect(
      container.read(liveTrackingProvider.notifier),
      isNot(same(liveNotifierA)),
    );
    expect(
      container.read(profileViewModelProvider.notifier),
      isNot(same(profileNotifierA)),
    );
    expect(
      container.read(calculatorProvider.notifier),
      isNot(same(calculatorNotifierA)),
    );
    expect(
      container.read(changePasswordProvider.notifier),
      isNot(same(passwordNotifierA)),
    );
    expect(
      container.read(syncCoordinatorProvider),
      isNot(same(syncCoordinatorA)),
    );
  });
}

class _ScopedWorkoutRepository implements WorkoutRepository {
  int currentUserId;
  final List<int> loadedUserIds = <int>[];

  _ScopedWorkoutRepository({required this.currentUserId});

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
    loadedUserIds.add(currentUserId);
    return PaginatedWorkouts(
      workouts: <WorkoutSessionEntity>[_workout(currentUserId)],
      currentPage: page,
      totalPages: 1,
      totalCount: 1,
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
    return const WorkoutStatistics(
      totalWorkouts: 1,
      totalDistance: 1000,
      averageDistance: 1000,
      totalCalories: 100,
      averageCalories: 100,
      maxDistance: 1000,
      totalDuration: Duration(minutes: 10),
      averageDuration: Duration(minutes: 10),
    );
  }

  @override
  Future<WorkoutSessionEntity?> getWorkout(int workoutId) async {
    return _workout(currentUserId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScopedImageRepository implements ActivityImageRepository {
  final _ScopedWorkoutRepository workoutRepository;

  _ScopedImageRepository(this.workoutRepository);

  @override
  Future<List<ActivityImageEntity>> getImagesForWorkout(
    int localWorkoutId,
  ) async {
    final userId = workoutRepository.currentUserId;
    final now = DateTime.utc(2026, 7, 11);
    return <ActivityImageEntity>[
      ActivityImageEntity(
        localId: userId,
        localWorkoutId: localWorkoutId,
        clientImageId: 'image-$userId',
        localPath: '/synthetic/image-$userId.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 10,
        status: ActivityImageSyncStatus.queued,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  @override
  Future<void> syncPendingImages() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAvatarRepository implements AvatarRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLiveTrackingRepository implements LiveTrackingRepository {
  @override
  Stream<TrackingPointEntity> get locationStream => const Stream.empty();

  @override
  DateTime now() => DateTime.utc(2026, 7, 11);

  @override
  Future<void> stopTracking() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WorkoutSessionEntity _workout(int userId) {
  return WorkoutSessionEntity(
    id: '$userId',
    clientSyncId: 'scope-$userId',
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    userId: userId,
  );
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
