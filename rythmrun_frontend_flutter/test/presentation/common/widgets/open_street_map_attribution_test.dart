import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/open_street_map_attribution.dart';

void main() {
  testWidgets('keeps OpenStreetMap attribution visible and links copyright', (
    tester,
  ) async {
    Uri? launchedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              OpenStreetMapAttribution(
                urlLauncher: (uri) async {
                  launchedUri = uri;
                  return true;
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byKey(const Key('openStreetMapAttribution')), findsOneWidget);

    await tester.tap(find.text('OpenStreetMap contributors'));
    await tester.pump();

    expect(launchedUri, Uri.parse('https://www.openstreetmap.org/copyright'));
  });
}
