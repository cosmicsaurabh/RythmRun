import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../common/providers/session_provider.dart';
import '../../../core/utils/feature_gate.dart';

/// Widget that shows connection status to the user
class ConnectionStatusIndicator extends ConsumerWidget {
  const ConnectionStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionData = ref.watch(sessionProvider);
    final isOffline = ref.watch(isOfflineModeProvider);

    if (!isOffline) {
      return const SizedBox.shrink(); // Don't show anything when online
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade300, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sessionData.errorMessage ??
                  'Offline mode - limited functionality',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (sessionData.errorMessage != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                // Try to refresh connection
                ref.read(sessionProvider.notifier).refreshSession();
              },
              child: Icon(
                Icons.refresh,
                size: 16,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A banner that can be shown at the top of screens to indicate offline mode
class OfflineModeBanner extends ConsumerWidget {
  const OfflineModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineModeProvider);

    if (!isOffline) {
      return const SizedBox.shrink();
    }

    return MaterialBanner(
      content: const Text(
        'You\'re offline. Some features may be limited.',
        style: TextStyle(fontSize: 14),
      ),
      backgroundColor: Colors.orange.shade50,
      leading: Icon(Icons.wifi_off, color: Colors.orange.shade700),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(sessionProvider.notifier).refreshSession();
          },
          child: Text('Retry', style: TextStyle(color: Colors.orange.shade700)),
        ),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: Text(
            'Dismiss',
            style: TextStyle(color: Colors.orange.shade700),
          ),
        ),
      ],
    );
  }
}

/// Feature disabled widget - shows when a feature is not available
class FeatureDisabledWidget extends ConsumerWidget {
  final String feature;
  final String? customMessage;
  final Widget? child;

  const FeatureDisabledWidget({
    super.key,
    required this.feature,
    this.customMessage,
    this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = ref.watch(featureGateProvider(feature));
    final message =
        customMessage != null
            ? customMessage!
            : ref.watch(featureMessageProvider(feature));

    if (isAvailable) {
      return child ?? const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
