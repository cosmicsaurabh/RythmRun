import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
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
    final activeUserId = int.tryParse(ref.watch(currentUserProvider)?.id ?? '');
    if (workoutId == null ||
        activeUserId == null ||
        widget.workout.userId != activeUserId) {
      return const SizedBox.shrink();
    }
    final providerKey = (userId: activeUserId, workoutId: workoutId);

    final state = ref.watch(activityImagesProvider(providerKey));
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
            _buildHeader(context, providerKey, state),
            if (state.errorMessage != null) ...[
              const SizedBox(height: spacingMd),
              _buildError(context, state.errorMessage!),
            ],
            const SizedBox(height: spacingMd),
            SizedBox(
              height: 132,
              child:
                  visibleImages.isEmpty
                      ? _buildEmptyState(context, providerKey)
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
                            onDelete: () => _deleteImage(providerKey, image),
                            onReplace: () => _replaceImage(providerKey, image),
                            onRetry: () => _retryImage(providerKey, image),
                            onRefreshRemoteUrls:
                                () => _refreshRemoteUrls(providerKey),
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
    ({int userId, int workoutId}) providerKey,
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
            onPressed: state.isLoading ? null : () => _attachImage(providerKey),
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

  Widget _buildEmptyState(
    BuildContext context,
    ({int userId, int workoutId}) providerKey,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(radiusMd),
      onTap: () => _attachImage(providerKey),
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

  Future<void> _attachImage(({int userId, int workoutId}) providerKey) async {
    final before = ref.read(activityImagesProvider(providerKey)).images.length;
    await ref
        .read(activityImagesProvider(providerKey).notifier)
        .attachFromGallery();
    if (!mounted) {
      return;
    }

    final after = ref.read(activityImagesProvider(providerKey)).images.length;
    if (after > before) {
      _showSnackBar(
        "Image saved on this device. It will upload when you're back online.",
      );
    }
  }

  Future<void> _deleteImage(
    ({int userId, int workoutId}) providerKey,
    ActivityImageEntity image,
  ) async {
    await ref
        .read(activityImagesProvider(providerKey).notifier)
        .deleteImage(image);
  }

  Future<void> _replaceImage(
    ({int userId, int workoutId}) providerKey,
    ActivityImageEntity image,
  ) async {
    await ref
        .read(activityImagesProvider(providerKey).notifier)
        .replaceImage(image);
  }

  Future<void> _retryImage(
    ({int userId, int workoutId}) providerKey,
    ActivityImageEntity image,
  ) async {
    await ref
        .read(activityImagesProvider(providerKey).notifier)
        .retryImage(image);
  }

  Future<void> _refreshRemoteUrls(
    ({int userId, int workoutId}) providerKey,
  ) async {
    await ref
        .read(activityImagesProvider(providerKey).notifier)
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
