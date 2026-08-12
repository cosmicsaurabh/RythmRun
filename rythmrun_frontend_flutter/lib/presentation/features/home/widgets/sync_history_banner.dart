import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../../core/di/injection_container.dart';

class SyncHistoryBanner extends ConsumerWidget {
  const SyncHistoryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(syncProgressProvider);
    if (progress != SyncProgress.restoring) {
      return const SizedBox.shrink();
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              isDarkMode
                  ? CustomAppColors.colorA.withValues(alpha: 0.15)
                  : CustomAppColors.colorA.withValues(alpha: 0.08),
          border: Border(
            bottom: BorderSide(
              color: CustomAppColors.colorA.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  CustomAppColors.colorA,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Restoring your workout history...',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      isDarkMode
                          ? CustomAppColors.white
                          : CustomAppColors.colorA,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
