import 'package:flutter/material.dart';
import '../../../const/custom_app_colors.dart';
import '../../../theme/app_theme.dart';

class ErrorDisplayWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onRetry;
  final bool isRetryEnabled;

  const ErrorDisplayWidget({
    super.key,
    required this.errorMessage,
    this.onRetry,
    this.isRetryEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isNetworkError = _isNetworkError(errorMessage);

    return Container(
      padding: const EdgeInsets.all(spacingMd),
      decoration: BoxDecoration(
        color: CustomAppColors.statusDanger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(color: CustomAppColors.statusDanger),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isNetworkError ? wifiOffIcon : errorOutlineIcon,
                color: CustomAppColors.statusDanger,
                size: iconSizeSm,
              ),
              const SizedBox(width: spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isNetworkError ? 'Connection Problem' : 'Error',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CustomAppColors.statusDanger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      errorMessage,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CustomAppColors.statusDanger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isNetworkError && onRetry != null && isRetryEnabled) ...[
            const SizedBox(height: spacingSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(refreshIcon, size: 16),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CustomAppColors.statusDanger,
                  side: BorderSide(color: CustomAppColors.statusDanger),
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isNetworkError(String message) {
    return message.toLowerCase().contains('unable to connect') ||
        message.toLowerCase().contains('connection') ||
        message.toLowerCase().contains('network') ||
        message.toLowerCase().contains('timeout') ||
        message.toLowerCase().contains('internet');
  }
}
