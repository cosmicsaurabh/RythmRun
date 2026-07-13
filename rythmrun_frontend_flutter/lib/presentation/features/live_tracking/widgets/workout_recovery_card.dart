import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class WorkoutRecoveryCard extends StatelessWidget {
  const WorkoutRecoveryCard({
    required this.savePending,
    required this.isBusy,
    required this.onRetry,
    required this.onDiscard,
    this.errorMessage,
    super.key,
  });

  final bool savePending;
  final bool isBusy;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final title = savePending ? 'Workout not saved' : 'Cleanup still pending';
    final fallbackMessage =
        savePending
            ? 'Your completed workout is still on this screen. Retry the local save before starting another workout.'
            : 'Your workout is saved, but location tracking still needs to finish shutting down.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          savePending ? Icons.cloud_off : Icons.location_disabled,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 40,
        ),
        const SizedBox(height: spacingMd),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: spacingSm),
        Text(
          errorMessage ?? fallbackMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onPrimary.withValues(alpha: 0.85),
            height: 1.35,
          ),
        ),
        const SizedBox(height: spacingLg),
        ElevatedButton.icon(
          key: const ValueKey('retry-workout-recovery'),
          onPressed: isBusy ? null : onRetry,
          icon:
              isBusy
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.refresh),
          label: Text(savePending ? 'Retry save' : 'Retry cleanup'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.onPrimary,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        if (savePending) ...[
          const SizedBox(height: spacingSm),
          TextButton(
            key: const ValueKey('discard-unsaved-workout'),
            onPressed: isBusy ? null : onDiscard,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Discard unsaved workout'),
          ),
        ],
      ],
    );
  }
}
