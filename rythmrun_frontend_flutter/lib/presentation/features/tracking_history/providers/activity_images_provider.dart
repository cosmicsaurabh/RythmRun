import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';

class ActivityImagesState {
  static const Object _unset = Object();

  final List<ActivityImageEntity> images;
  final bool isLoading;
  final String? errorMessage;

  const ActivityImagesState({
    this.images = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ActivityImagesState copyWith({
    List<ActivityImageEntity>? images,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return ActivityImagesState(
      images: images ?? this.images,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          identical(errorMessage, _unset)
              ? this.errorMessage
              : errorMessage as String?,
    );
  }
}

final activityImagesProvider = StateNotifierProvider.autoDispose.family<
  ActivityImagesNotifier,
  ActivityImagesState,
  ({int userId, int workoutId})
>((ref, key) {
  final operationGate = ref.watch(userScopeOperationGateProvider);
  return ActivityImagesNotifier(
    repository: ref.watch(activityImageRepositoryProvider),
    workoutId: key.workoutId,
    expectedUserId: key.userId,
    isExpectedOwnerActive:
        (expectedUserId) =>
            !operationGate.isSuspended &&
            operationGate.activeUserId == expectedUserId,
  )..load();
});

class ActivityImagesNotifier extends StateNotifier<ActivityImagesState> {
  static const String _ownerErrorMessage =
      'Workout images are not available for this account.';

  final ActivityImageRepository _repository;
  final int _workoutId;
  final int _expectedUserId;
  final bool Function(int expectedUserId) _isExpectedOwnerActive;
  final ImagePicker _imagePicker;
  bool _isDisposed = false;

  ActivityImagesNotifier({
    required ActivityImageRepository repository,
    required int workoutId,
    required int expectedUserId,
    bool Function(int expectedUserId)? isExpectedOwnerActive,
    ImagePicker? imagePicker,
  }) : _repository = repository,
       _workoutId = workoutId,
       _expectedUserId = expectedUserId,
       _isExpectedOwnerActive = isExpectedOwnerActive ?? ((_) => true),
       _imagePicker = imagePicker ?? ImagePicker(),
       super(const ActivityImagesState());

  Future<void> load() async {
    if (!_ensureExpectedOwner()) return;
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      final images = await _repository.getImagesForWorkout(_workoutId);
      if (!_ensureExpectedOwner()) return;
      if (images.any((image) => image.localWorkoutId != _workoutId)) {
        state = state.copyWith(
          images: const <ActivityImageEntity>[],
          isLoading: false,
          errorMessage: 'Workout images returned an invalid owner scope.',
        );
        return;
      }
      state = state.copyWith(images: images, isLoading: false);
    } catch (error) {
      if (_isDisposed) return;
      if (!_ensureExpectedOwner()) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load images: $error',
      );
    }
  }

  Future<void> attachFromGallery() async {
    if (!_ensureExpectedOwner()) return;
    try {
      state = state.copyWith(errorMessage: null);
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (!_ensureExpectedOwner()) return;
      if (image == null) {
        return;
      }

      await _repository.attachImage(localWorkoutId: _workoutId, image: image);
      if (!_ensureExpectedOwner()) return;
      await load();
    } catch (error) {
      if (_isDisposed) return;
      if (!_ensureExpectedOwner()) return;
      state = state.copyWith(errorMessage: 'Failed to attach image: $error');
    }
  }

  Future<void> deleteImage(ActivityImageEntity image) async {
    if (!_ensureExpectedOwner() || !_ensureExpectedWorkout(image)) return;
    final localId = image.localId;
    if (localId == null) {
      return;
    }

    try {
      state = state.copyWith(errorMessage: null);
      await _repository.deleteImage(localId);
      if (!_ensureExpectedOwner()) return;
      await load();
    } catch (error) {
      if (_isDisposed) return;
      if (!_ensureExpectedOwner()) return;
      state = state.copyWith(errorMessage: 'Failed to delete image: $error');
    }
  }

  Future<void> replaceImage(ActivityImageEntity image) async {
    if (!_ensureExpectedOwner() || !_ensureExpectedWorkout(image)) return;
    final localId = image.localId;
    if (localId == null) {
      return;
    }

    try {
      state = state.copyWith(errorMessage: null);
      final replacement = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (!_ensureExpectedOwner()) return;
      if (replacement == null) {
        return;
      }

      await _repository.replaceImage(
        oldLocalImageId: localId,
        newImage: replacement,
      );
      if (!_ensureExpectedOwner()) return;
      await load();
    } catch (error) {
      if (_isDisposed) return;
      if (!_ensureExpectedOwner()) return;
      state = state.copyWith(errorMessage: 'Failed to replace image: $error');
    }
  }

  Future<void> retryImage(ActivityImageEntity image) async {
    if (!_ensureExpectedOwner() || !_ensureExpectedWorkout(image)) return;
    final localId = image.localId;
    if (localId == null) {
      return;
    }

    try {
      state = state.copyWith(errorMessage: null);
      await _repository.retryImage(localId);
      if (!_ensureExpectedOwner()) return;
      await load();
    } catch (error) {
      if (_isDisposed) return;
      if (!_ensureExpectedOwner()) return;
      state = state.copyWith(errorMessage: 'Failed to retry image: $error');
    }
  }

  Future<void> refreshRemoteUrls() async {
    if (!_ensureExpectedOwner()) return;
    try {
      state = state.copyWith(errorMessage: null);
      await _repository.refreshRemoteImagesForWorkout(_workoutId);
      if (!_ensureExpectedOwner()) return;
      await load();
    } catch (error) {
      if (_isDisposed) return;
      if (!_ensureExpectedOwner()) return;
      state = state.copyWith(errorMessage: 'Failed to refresh images: $error');
    }
  }

  bool _ensureExpectedOwner() {
    if (_isDisposed) {
      return false;
    }
    if (_expectedUserId > 0 && _isExpectedOwnerActive(_expectedUserId)) {
      return true;
    }

    state = state.copyWith(
      images: const <ActivityImageEntity>[],
      isLoading: false,
      errorMessage: _ownerErrorMessage,
    );
    return false;
  }

  bool _ensureExpectedWorkout(ActivityImageEntity image) {
    if (image.localWorkoutId == _workoutId) {
      return true;
    }

    state = state.copyWith(
      errorMessage: 'Image is not available for this workout.',
    );
    return false;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
