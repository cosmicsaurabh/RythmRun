import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/widgets/activity_image_tile.dart';

void main() {
  testWidgets('retry menu action calls onRetry', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 132,
            height: 132,
            child: ActivityImageTile(
              image: ActivityImageEntity(
                localId: 1,
                localWorkoutId: 42,
                clientImageId: 'img_client_123456',
                localPath: '/missing/activity-image.jpg',
                thumbnailPath: '/missing/activity-image-thumb.jpg',
                contentType: 'image/jpeg',
                sizeBytes: 1024,
                status: ActivityImageSyncStatus.failed,
                createdAt: DateTime(2026, 6, 9, 8),
                updatedAt: DateTime(2026, 6, 9, 8),
              ),
              onDelete: () {},
              onReplace: () {},
              onRetry: () => retryCount++,
              onRefreshRemoteUrls: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byTooltip('Image actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(retryCount, 1);
  });
}
