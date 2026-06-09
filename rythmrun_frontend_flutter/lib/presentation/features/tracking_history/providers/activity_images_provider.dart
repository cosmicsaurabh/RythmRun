import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/activity_image_repository.dart';

class ActivityImagesState {
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
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActivityImagesState(
      images: images ?? this.images,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final activityImagesProvider = StateNotifierProvider.autoDispose
    .family<ActivityImagesNotifier, ActivityImagesState, int>((ref, workoutId) {
      return ActivityImagesNotifier(
        repository: ref.watch(activityImageRepositoryProvider),
        workoutId: workoutId,
      )..load();
    });

class ActivityImagesNotifier extends StateNotifier<ActivityImagesState> {
  final ActivityImageRepository _repository;
  final int _workoutId;
  final ImagePicker _imagePicker;

  ActivityImagesNotifier({
    required ActivityImageRepository repository,
    required int workoutId,
    ImagePicker? imagePicker,
  }) : _repository = repository,
       _workoutId = workoutId,
       _imagePicker = imagePicker ?? ImagePicker(),
       super(const ActivityImagesState());

  Future<void> load() async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final images = await _repository.getImagesForWorkout(_workoutId);
      state = state.copyWith(images: images, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load images: $error',
      );
    }
  }

  Future<void> attachFromGallery() async {
    try {
      state = state.copyWith(clearError: true);
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        return;
      }

      await _repository.attachImage(localWorkoutId: _workoutId, image: image);
      await load();
    } catch (error) {
      state = state.copyWith(errorMessage: 'Failed to attach image: $error');
    }
  }

  Future<void> deleteImage(ActivityImageEntity image) async {
    final localId = image.localId;
    if (localId == null) {
      return;
    }

    try {
      state = state.copyWith(clearError: true);
      await _repository.deleteImage(localId);
      await load();
    } catch (error) {
      state = state.copyWith(errorMessage: 'Failed to delete image: $error');
    }
  }

  Future<void> replaceImage(ActivityImageEntity image) async {
    final localId = image.localId;
    if (localId == null) {
      return;
    }

    try {
      state = state.copyWith(clearError: true);
      final replacement = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (replacement == null) {
        return;
      }

      await _repository.replaceImage(
        oldLocalImageId: localId,
        newImage: replacement,
      );
      await load();
    } catch (error) {
      state = state.copyWith(errorMessage: 'Failed to replace image: $error');
    }
  }

  Future<void> retryImage(ActivityImageEntity image) async {
    final localId = image.localId;
    if (localId == null) {
      return;
    }

    try {
      state = state.copyWith(clearError: true);
      await _repository.retryImage(localId);
      await load();
    } catch (error) {
      state = state.copyWith(errorMessage: 'Failed to retry image: $error');
    }
  }

  Future<void> refreshRemoteUrls() async {
    try {
      state = state.copyWith(clearError: true);
      await _repository.refreshRemoteImagesForWorkout(_workoutId);
      await load();
    } catch (error) {
      state = state.copyWith(errorMessage: 'Failed to refresh images: $error');
    }
  }
}
