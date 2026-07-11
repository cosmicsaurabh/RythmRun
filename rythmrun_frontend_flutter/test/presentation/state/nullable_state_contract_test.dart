import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/models/login_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/models/registration_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/settings/models/change_password_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_details_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/activity_images_provider.dart';

void main() {
  group('nullable copyWith contract', () {
    test('login and registration errors distinguish omitted from null', () {
      const login = LoginState(errorMessage: 'login failed');
      const registration = RegistrationState(errorMessage: 'register failed');

      expect(login.copyWith().errorMessage, 'login failed');
      expect(login.copyWith(errorMessage: null).errorMessage, isNull);
      expect(registration.copyWith().errorMessage, 'register failed');
      expect(registration.copyWith(errorMessage: null).errorMessage, isNull);
    });

    test('change-password error distinguishes omitted from null', () {
      const original = ChangePasswordState(errorMessage: 'change failed');

      expect(original.copyWith().errorMessage, 'change failed');
      expect(original.copyWith(errorMessage: null).errorMessage, isNull);
      expect(original.clearError().errorMessage, isNull);
    });

    test('history details can clear both workout and error', () {
      final workout = _workout('details');
      final original = TrackingHistoryDetailsState(
        workout: workout,
        errorMessage: 'details failed',
      );

      final retained = original.copyWith();
      expect(retained.workout, same(workout));
      expect(retained.errorMessage, 'details failed');

      final cleared = original.copyWith(workout: null, errorMessage: null);
      expect(cleared.workout, isNull);
      expect(cleared.errorMessage, isNull);
    });

    test('history can clear every nullable field', () {
      final start = DateTime.utc(2026, 7, 1);
      final end = DateTime.utc(2026, 7, 2);
      final overall = _statistics(1);
      final filtered = _statistics(2);
      final original = TrackingHistoryState(
        errorMessage: 'history failed',
        selectedWorkoutType: 'running',
        startDate: start,
        endDate: end,
        searchQuery: 'morning',
        overallStatistics: overall,
        filteredStatistics: filtered,
      );

      final retained = original.copyWith();
      expect(retained.errorMessage, 'history failed');
      expect(retained.selectedWorkoutType, 'running');
      expect(retained.startDate, start);
      expect(retained.endDate, end);
      expect(retained.searchQuery, 'morning');
      expect(retained.overallStatistics, same(overall));
      expect(retained.filteredStatistics, same(filtered));

      final cleared = original.copyWith(
        errorMessage: null,
        selectedWorkoutType: null,
        startDate: null,
        endDate: null,
        searchQuery: null,
        overallStatistics: null,
        filteredStatistics: null,
      );
      expect(cleared.errorMessage, isNull);
      expect(cleared.selectedWorkoutType, isNull);
      expect(cleared.startDate, isNull);
      expect(cleared.endDate, isNull);
      expect(cleared.searchQuery, isNull);
      expect(cleared.overallStatistics, isNull);
      expect(cleared.filteredStatistics, isNull);
    });

    test('clearFilters only clears filters and resets the page', () {
      final statistics = _statistics(3);
      final original = TrackingHistoryState(
        currentPage: 4,
        errorMessage: 'keep this error',
        selectedWorkoutType: 'cycling',
        startDate: DateTime.utc(2026, 7, 1),
        endDate: DateTime.utc(2026, 7, 2),
        searchQuery: 'commute',
        overallStatistics: statistics,
      );

      final cleared = original.clearFilters();

      expect(cleared.currentPage, 1);
      expect(cleared.hasFilters, isFalse);
      expect(cleared.errorMessage, 'keep this error');
      expect(cleared.overallStatistics, same(statistics));
    });

    test('activity-image error distinguishes omitted from null', () {
      const original = ActivityImagesState(errorMessage: 'image failed');

      expect(original.copyWith().errorMessage, 'image failed');
      expect(original.copyWith(errorMessage: null).errorMessage, isNull);
    });

    test('user avatar metadata and creation date can be cleared', () {
      final createdAt = DateTime.utc(2026, 7, 1);
      final original = UserEntity(
        id: '7',
        firstName: 'A',
        lastName: 'Runner',
        email: 'a@example.com',
        profilePicturePath: 'avatars/7/current.jpg',
        profilePictureType: 'image/jpeg',
        createdAt: createdAt,
      );

      final retained = original.copyWith();
      expect(retained.profilePicturePath, original.profilePicturePath);
      expect(retained.profilePictureType, original.profilePictureType);
      expect(retained.createdAt, createdAt);

      final cleared = original.copyWith(
        profilePicturePath: null,
        profilePictureType: null,
        createdAt: null,
      );
      expect(cleared.profilePicturePath, isNull);
      expect(cleared.profilePictureType, isNull);
      expect(cleared.createdAt, isNull);
    });
  });
}

WorkoutSessionEntity _workout(String id) {
  return WorkoutSessionEntity(
    id: id,
    clientSyncId: 'client-$id',
    type: WorkoutType.running,
    status: WorkoutStatus.completed,
    userId: 7,
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
