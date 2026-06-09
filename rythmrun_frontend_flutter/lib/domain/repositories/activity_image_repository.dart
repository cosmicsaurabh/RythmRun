import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';

abstract class ActivityImageRepository {
  Future<ActivityImageEntity> attachImage({
    required int localWorkoutId,
    required XFile image,
  });

  Future<void> deleteImage(int localImageId);

  Future<ActivityImageEntity> replaceImage({
    required int oldLocalImageId,
    required XFile newImage,
  });

  Future<List<ActivityImageEntity>> getImagesForWorkout(int localWorkoutId);

  Future<void> retryImage(int localImageId);

  Future<void> refreshRemoteImagesForWorkout(int localWorkoutId);

  Future<void> syncPendingImages();
}
