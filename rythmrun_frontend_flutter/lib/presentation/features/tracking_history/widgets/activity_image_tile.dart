import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class ActivityImageTile extends StatefulWidget {
  final ActivityImageEntity image;
  final VoidCallback onDelete;
  final VoidCallback onReplace;
  final VoidCallback onRetry;
  final VoidCallback onRefreshRemoteUrls;

  const ActivityImageTile({
    super.key,
    required this.image,
    required this.onDelete,
    required this.onReplace,
    required this.onRetry,
    required this.onRefreshRemoteUrls,
  });

  @override
  State<ActivityImageTile> createState() => _ActivityImageTileState();
}

class _ActivityImageTileState extends State<ActivityImageTile> {
  bool _refreshRequested = false;

  @override
  void didUpdateWidget(ActivityImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.remoteUrl != widget.image.remoteUrl ||
        oldWidget.image.remoteUrlExpiresAt != widget.image.remoteUrlExpiresAt) {
      _refreshRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radiusMd),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<_ActivityImageSource>(
              future: _resolveImageSource(widget.image),
              builder: (context, snapshot) {
                final source = snapshot.data;
                if (source == null) {
                  return _buildPlaceholder(context, Icons.image_outlined);
                }

                return _buildImage(context, source);
              },
            ),
            Positioned(
              left: spacingSm,
              right: spacingSm,
              bottom: spacingSm,
              child: _buildStatusBadge(context),
            ),
            Positioned(
              top: spacingXs,
              right: spacingXs,
              child: _buildActions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, _ActivityImageSource source) {
    if (source.type == _ActivityImageSourceType.file) {
      return Image.file(
        File(source.value),
        fit: BoxFit.cover,
        errorBuilder:
            (context, error, stackTrace) =>
                _buildPlaceholder(context, Icons.broken_image),
      );
    }

    if (source.type == _ActivityImageSourceType.placeholder) {
      return _buildPlaceholder(context, Icons.broken_image);
    }

    return Image.network(
      source.value,
      fit: BoxFit.cover,
      errorBuilder:
          (context, error, stackTrace) =>
              _buildPlaceholder(context, Icons.broken_image),
    );
  }

  Widget _buildPlaceholder(BuildContext context, IconData icon) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Icon(icon, color: CustomAppColors.secondaryText, size: 28),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final statusMessage = imageStatusMessage(widget.image.status);
    return Tooltip(
      message: statusMessage ?? imageStatusLabel(widget.image.status),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: spacingSm,
          vertical: spacingXs,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Text(
          imageStatusLabel(widget.image.status),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final actions = _availableActions(widget.image.status);
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      child: PopupMenuButton<_ActivityImageAction>(
        tooltip: 'Image actions',
        icon: const Icon(Icons.more_horiz, color: Colors.white, size: 18),
        onSelected: _handleAction,
        itemBuilder:
            (context) =>
                actions.map((action) {
                  return PopupMenuItem<_ActivityImageAction>(
                    value: action,
                    child: Row(
                      children: [
                        Icon(_actionIcon(action), size: 18),
                        const SizedBox(width: spacingSm),
                        Text(_actionLabel(action)),
                      ],
                    ),
                  );
                }).toList(),
      ),
    );
  }

  void _handleAction(_ActivityImageAction action) {
    switch (action) {
      case _ActivityImageAction.delete:
        widget.onDelete();
        break;
      case _ActivityImageAction.replace:
        widget.onReplace();
        break;
      case _ActivityImageAction.retry:
        widget.onRetry();
        break;
    }
  }

  List<_ActivityImageAction> _availableActions(ActivityImageSyncStatus status) {
    switch (status) {
      case ActivityImageSyncStatus.queued:
      case ActivityImageSyncStatus.waitingForActivitySync:
        return const [_ActivityImageAction.delete];
      case ActivityImageSyncStatus.retrying:
      case ActivityImageSyncStatus.failed:
        return const [_ActivityImageAction.retry, _ActivityImageAction.delete];
      case ActivityImageSyncStatus.uploading:
        return const [_ActivityImageAction.delete];
      case ActivityImageSyncStatus.uploaded:
        return const [
          _ActivityImageAction.replace,
          _ActivityImageAction.delete,
        ];
      case ActivityImageSyncStatus.replaceQueued:
        return const [_ActivityImageAction.delete];
      case ActivityImageSyncStatus.deleteQueued:
      case ActivityImageSyncStatus.deleting:
      case ActivityImageSyncStatus.deleted:
        return const [];
    }
  }

  IconData _actionIcon(_ActivityImageAction action) {
    switch (action) {
      case _ActivityImageAction.delete:
        return Icons.delete_outline;
      case _ActivityImageAction.replace:
        return Icons.swap_horiz;
      case _ActivityImageAction.retry:
        return Icons.refresh;
    }
  }

  String _actionLabel(_ActivityImageAction action) {
    switch (action) {
      case _ActivityImageAction.delete:
        return 'Delete';
      case _ActivityImageAction.replace:
        return 'Replace';
      case _ActivityImageAction.retry:
        return 'Retry';
    }
  }

  Future<_ActivityImageSource> _resolveImageSource(
    ActivityImageEntity image,
  ) async {
    final thumbnailPath = image.thumbnailPath;
    if (thumbnailPath != null && await File(thumbnailPath).exists()) {
      return _ActivityImageSource.file(thumbnailPath);
    }

    if (await File(image.localPath).exists()) {
      return _ActivityImageSource.file(image.localPath);
    }

    final remoteUrl = image.remoteUrl;
    final remoteUrlExpiresAt = image.remoteUrlExpiresAt;
    if (remoteUrl != null &&
        remoteUrl.isNotEmpty &&
        remoteUrlExpiresAt != null &&
        remoteUrlExpiresAt.isAfter(
          DateTime.now().add(const Duration(seconds: 60)),
        )) {
      return _ActivityImageSource.network(remoteUrl);
    }

    if (!_refreshRequested) {
      _refreshRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onRefreshRemoteUrls();
        }
      });
    }

    return _ActivityImageSource.placeholder();
  }
}

String imageStatusLabel(ActivityImageSyncStatus status) {
  switch (status) {
    case ActivityImageSyncStatus.queued:
      return 'Queued';
    case ActivityImageSyncStatus.waitingForActivitySync:
      return 'Waiting for activity sync';
    case ActivityImageSyncStatus.uploading:
      return 'Uploading';
    case ActivityImageSyncStatus.uploaded:
      return 'Uploaded';
    case ActivityImageSyncStatus.retrying:
      return 'Retrying';
    case ActivityImageSyncStatus.failed:
      return 'Failed';
    case ActivityImageSyncStatus.deleteQueued:
      return 'Delete queued';
    case ActivityImageSyncStatus.deleting:
      return 'Deleting';
    case ActivityImageSyncStatus.deleted:
      return 'Deleted';
    case ActivityImageSyncStatus.replaceQueued:
      return 'Replacing';
  }
}

String? imageStatusMessage(ActivityImageSyncStatus status) {
  switch (status) {
    case ActivityImageSyncStatus.retrying:
      return "Upload failed. We'll retry automatically.";
    case ActivityImageSyncStatus.failed:
      return 'Upload failed. Please retry or remove this image.';
    default:
      return null;
  }
}

enum _ActivityImageAction { delete, replace, retry }

enum _ActivityImageSourceType { file, network, placeholder }

class _ActivityImageSource {
  final _ActivityImageSourceType type;
  final String value;

  const _ActivityImageSource(this.type, this.value);

  factory _ActivityImageSource.file(String path) {
    return _ActivityImageSource(_ActivityImageSourceType.file, path);
  }

  factory _ActivityImageSource.network(String url) {
    return _ActivityImageSource(_ActivityImageSourceType.network, url);
  }

  factory _ActivityImageSource.placeholder() {
    return const _ActivityImageSource(_ActivityImageSourceType.placeholder, '');
  }
}
