import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../common/providers/connectivity_provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../const/custom_app_colors.dart';
import '../../../theme/app_theme.dart';

/// Reusable connectivity badge widget for app bars
/// Subtle design aligned with app's aesthetic
class ConnectivityBadge extends ConsumerWidget {
  /// Whether to show the badge only when there's an issue (default: true)
  final bool showOnlyWhenIssue;

  /// Custom icon size (default: 20)
  final double? iconSize;

  /// Whether to show text label (default: true)
  final bool showLabel;

  const ConnectivityBadge({
    super.key,
    this.showOnlyWhenIssue = true,
    this.iconSize,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityStatus = ref.watch(currentConnectivityStatusProvider);

    // If showing only when there's an issue and we're connected, return empty
    if (showOnlyWhenIssue &&
        connectivityStatus == ConnectivityStatus.connected) {
      return const SizedBox.shrink();
    }

    return _buildBadge(context, connectivityStatus);
  }

  Widget _buildBadge(BuildContext context, ConnectivityStatus status) {
    final iconSizeValue = iconSize ?? iconSizeSm;

    switch (status) {
      case ConnectivityStatus.slow:
        return _buildSlowInternetBadge(context, iconSizeValue);
      case ConnectivityStatus.disconnected:
        return _buildNoInternetBadge(context, iconSizeValue);
      case ConnectivityStatus.connected:
        return _buildConnectedBadge(context, iconSizeValue);
    }
  }

  Widget _buildSlowInternetBadge(BuildContext context, double iconSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = CustomAppColors.statusWarning;
    final backgroundColor =
        isDark
            ? CustomAppColors.statusWarning.withOpacity(0.15)
            : CustomAppColors.statusWarning.withOpacity(0.1);

    if (showLabel) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: spacingSm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(
              color: CustomAppColors.statusWarning.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.signal_wifi_statusbar_connected_no_internet_4,
                size: iconSize,
                color: iconColor,
              ),
              const SizedBox(width: spacingXs),
              Text(
                'Slow',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Icon-only version with subtle indicator
    return Align(
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(spacingXs),
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.signal_wifi_statusbar_connected_no_internet_4,
              size: iconSize,
              color: iconColor,
            ),
          ),
          // Subtle indicator dot
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isDark
                          ? CustomAppColors.surfaceBackgroundDark
                          : CustomAppColors.white,
                  width: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoInternetBadge(BuildContext context, double iconSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = CustomAppColors.statusError;
    final backgroundColor =
        isDark
            ? CustomAppColors.statusError.withOpacity(0.15)
            : CustomAppColors.statusError.withOpacity(0.1);

    if (showLabel) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: spacingSm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(
              color: CustomAppColors.statusError.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: iconSize, color: iconColor),
              const SizedBox(width: spacingXs),
              Text(
                'Offline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Icon-only version with subtle indicator
    return Align(
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(spacingXs),
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wifi_off, size: iconSize, color: iconColor),
          ),
          // Subtle indicator dot
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isDark
                          ? CustomAppColors.surfaceBackgroundDark
                          : CustomAppColors.white,
                  width: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedBadge(BuildContext context, double iconSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = CustomAppColors.statusSuccess;
    final backgroundColor =
        isDark
            ? CustomAppColors.statusSuccess.withOpacity(0.15)
            : CustomAppColors.statusSuccess.withOpacity(0.1);

    if (showLabel) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: spacingSm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(
              color: CustomAppColors.statusSuccess.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi, size: iconSize, color: iconColor),
              const SizedBox(width: spacingXs),
              Text(
                'Online',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(spacingXs),
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.wifi, size: iconSize, color: iconColor),
      ),
    );
  }
}

/// Compact version of connectivity badge (icon only, no text)
/// Minimal design with subtle indicator dot
class ConnectivityBadgeCompact extends StatelessWidget {
  final double? iconSize;

  const ConnectivityBadgeCompact({super.key, this.iconSize});

  @override
  Widget build(BuildContext context) {
    return ConnectivityBadge(
      showOnlyWhenIssue: true,
      iconSize: iconSize,
      showLabel: false,
    );
  }
}
