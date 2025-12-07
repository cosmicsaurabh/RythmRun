import 'package:flutter/material.dart';

enum StartOfDayOfferAction { watchNow, skip }

Future<StartOfDayOfferAction?> showStartOfDayOfferPrompt(BuildContext context) {
  return showDialog<StartOfDayOfferAction>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Unlock an Ad-Free Day'),
        content: const Text(
          'Watch one short ad now to enjoy the rest of the day without '
          'post-activity ads. Prefer not to? No problem — we\'ll just show a '
          'quick ad after you finish your next activity.',
        ),
        actions: [
          TextButton(
            onPressed:
                () => Navigator.of(context).pop(StartOfDayOfferAction.skip),
            child: const Text('Maybe later'),
          ),
          FilledButton.icon(
            onPressed:
                () => Navigator.of(context).pop(StartOfDayOfferAction.watchNow),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Watch & unlock'),
          ),
        ],
      );
    },
  );
}
