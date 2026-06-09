import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/activity_images_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/widgets/activity_image_tile.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class ActivityImageStrip extends ConsumerStatefulWidget {
  final WorkoutSessionEntity workout;

  const ActivityImageStrip({super.key, required this.workout});

  @override
  ConsumerState<ActivityImageStrip> createState() => _ActivityImageStripState();
}

class _ActivityImageStripState extends ConsumerState<ActivityImageStrip> {
  @override
  Widget build(BuildContext context) {
    final workoutId = int.tryParse(widget.workout.id ?? '');
    if (workoutId == null) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(activityImagesProvider(workoutId));
    final visibleImages =
        state.images.where((image) => _isVisible(image.status)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spacingMd),
      child: Container(
        padding: const EdgeInsets.all(spacingLg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(radiusLg),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, workoutId, state),
            if (state.errorMessage != null) ...[
              const SizedBox(height: spacingMd),
              _buildError(context, state.errorMessage!),
            ],
            const SizedBox(height: spacingMd),
            SizedBox(
              height: 132,
              child:
                  visibleImages.isEmpty
                      ? _buildEmptyState(context, workoutId)
                      : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: visibleImages.length,
                        separatorBuilder:
                            (context, index) =>
                                const SizedBox(width: spacingMd),
                        itemBuilder: (context, index) {
                          final image = visibleImages[index];
                          return ActivityImageTile(
                            image: image,
                            onDelete: () => _deleteImage(workoutId, image),
                            onReplace: () => _replaceImage(workoutId, image),
                            onRetry: () => _retryImage(workoutId, image),
                            onRefreshRemoteUrls:
                                () => _refreshRemoteUrls(workoutId),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    int workoutId,
    ActivityImagesState state,
  ) {
    return Row(
      children: [
        Icon(
          Icons.photo_library_outlined,
          color: CustomAppColors.secondaryText,
        ),
        const SizedBox(width: spacingSm),
        Expanded(
          child: Text(
            'Photos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: CustomAppColors.secondaryText,
            ),
          ),
        ),
        if (state.isLoading) ...[
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: spacingSm),
        ],
        Tooltip(
          message: 'Add photo',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.isLoading ? null : () => _attachImage(workoutId),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(spacingSm),
      decoration: BoxDecoration(
        color: CustomAppColors.statusError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(
          color: CustomAppColors.statusError.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: CustomAppColors.statusError),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, int workoutId) {
    return InkWell(
      borderRadius: BorderRadius.circular(radiusMd),
      onTap: () => _attachImage(workoutId),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: CustomAppColors.secondaryText.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(
            color: CustomAppColors.secondaryText.withValues(alpha: 0.16),
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add_photo_alternate_outlined,
            color: CustomAppColors.secondaryText,
            size: 32,
          ),
        ),
      ),
    );
  }

  Future<void> _attachImage(int workoutId) async {
    final before = ref.read(activityImagesProvider(workoutId)).images.length;
    await ref
        .read(activityImagesProvider(workoutId).notifier)
        .attachFromGallery();
    if (!mounted) {
      return;
    }

    final after = ref.read(activityImagesProvider(workoutId)).images.length;
    if (after > before) {
      _showSnackBar(
        "Image saved on this device. It will upload when you're back online.",
      );
    }
  }

  Future<void> _deleteImage(int workoutId, ActivityImageEntity image) async {
    await ref
        .read(activityImagesProvider(workoutId).notifier)
        .deleteImage(image);
  }

  Future<void> _replaceImage(int workoutId, ActivityImageEntity image) async {
    await ref
        .read(activityImagesProvider(workoutId).notifier)
        .replaceImage(image);
  }

  Future<void> _retryImage(int workoutId, ActivityImageEntity image) async {
    await ref
        .read(activityImagesProvider(workoutId).notifier)
        .retryImage(image);
  }

  Future<void> _refreshRemoteUrls(int workoutId) async {
    await ref
        .read(activityImagesProvider(workoutId).notifier)
        .refreshRemoteUrls();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _isVisible(ActivityImageSyncStatus status) {
    return status != ActivityImageSyncStatus.deleteQueued &&
        status != ActivityImageSyncStatus.deleting &&
        status != ActivityImageSyncStatus.deleted;
  }
}
