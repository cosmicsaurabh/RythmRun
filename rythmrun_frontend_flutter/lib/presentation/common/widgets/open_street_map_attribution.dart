import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

typedef AttributionUrlLauncher = Future<bool> Function(Uri uri);

const _openStreetMapCopyrightUrl = 'https://www.openstreetmap.org/copyright';

Future<bool> _launchAttributionUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Always-visible attribution for maps backed by OpenStreetMap's public tiles.
class OpenStreetMapAttribution extends StatelessWidget {
  const OpenStreetMapAttribution({super.key, this.urlLauncher});

  final AttributionUrlLauncher? urlLauncher;

  Future<void> _openCopyrightPage() async {
    final launcher = urlLauncher ?? _launchAttributionUrl;
    await launcher(Uri.parse(_openStreetMapCopyrightUrl));
  }

  @override
  Widget build(BuildContext context) {
    return SimpleAttributionWidget(
      key: const Key('openStreetMapAttribution'),
      source: const Text(
        'OpenStreetMap contributors',
        style: TextStyle(decoration: TextDecoration.underline),
      ),
      onTap: () => unawaited(_openCopyrightPage()),
      alignment: Alignment.bottomLeft,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.88),
    );
  }
}
