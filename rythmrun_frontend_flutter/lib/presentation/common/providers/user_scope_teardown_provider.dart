import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/providers/calculator_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/home/screens/home_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/providers/login_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/profile/providers/profile_view_model.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/providers/registration_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/settings/providers/change_password_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/activity_images_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_details_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';

final Provider<UserScopeTeardown>
userScopeTeardownProvider = Provider<UserScopeTeardown>((ref) {
  final operationGate = ref.watch(userScopeOperationGateProvider);
  String? activeUserId;

  void invalidateUserState({bool includeEntryForms = true}) {
    ref.invalidate(liveTrackingProvider);
    ref.invalidate(trackingHistoryProvider);
    ref.invalidate(trackingHistoryDetailsProvider);
    ref.invalidate(activityImagesProvider);
    ref.invalidate(profileViewModelProvider);
    ref.invalidate(changePasswordProvider);
    if (includeEntryForms) {
      ref.invalidate(loginProvider);
      ref.invalidate(registrationProvider);
    }
    ref.invalidate(calculatorProvider);
    ref.invalidate(tabIndexProvider);
    ref.invalidate(syncCoordinatorProvider);
    ref.invalidate(workoutRepositoryProvider);
    ref.invalidate(activityImageRepositoryProvider);
    ref.invalidate(avatarRepositoryProvider);
    activeUserId = null;
  }

  void activateWork(String userId) {
    final numericUserId = int.tryParse(userId);
    if (numericUserId == null || numericUserId <= 0) {
      throw StateError('Authenticated user ID must be a positive integer.');
    }
    if (activeUserId != null && activeUserId != userId) {
      throw StateError(
        'The previous user scope must be torn down before account switch.',
      );
    }
    if (activeUserId == userId) {
      ref.read(liveTrackingProvider.notifier).resumeAfterBlockedAccountExit();
    }
    if (activeUserId != userId) {
      // Providers can be recreated by still-mounted widgets between teardown
      // and the auth-state frame. Clear them again before publishing B.
      invalidateUserState(includeEntryForms: false);
    }
    operationGate.activate(numericUserId);
    activeUserId = userId;
  }

  return DefaultUserScopeTeardown(
    hasActiveWorkout: () => ref.read(liveTrackingProvider).hasActiveSession,
    hasUnsavedWorkout:
        () =>
            ref.read(liveTrackingProvider.notifier).hasUnsavedCompletedWorkout,
    hasPendingTrackingCleanup:
        () => ref.read(liveTrackingProvider.notifier).hasPendingTrackingCleanup,
    quiesceTrackingOperations:
        () => ref.read(liveTrackingProvider.notifier).quiesceForAccountExit(),
    finishWorkout: () async {
      final result =
          await ref.read(liveTrackingProvider.notifier).stopWorkout();
      return result.isDurablySaved &&
          !ref.read(liveTrackingProvider.notifier).hasUnsavedCompletedWorkout;
    },
    retryWorkoutSave:
        () => ref.read(liveTrackingProvider.notifier).retryUnsavedWorkoutSave(),
    retryTrackingCleanup:
        () =>
            ref
                .read(liveTrackingProvider.notifier)
                .retryPendingTrackingCleanup(),
    discardWorkout:
        () => ref
            .read(liveTrackingProvider.notifier)
            .discardWorkout(forAccountExit: true),
    suspendAndDrainWork: operationGate.suspendAndDrain,
    invalidateUserState: invalidateUserState,
    activateWork: activateWork,
  );
});
