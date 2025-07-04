import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/quick_action_card.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../live_tracking/screens/live_tracking_screen.dart';

class TrackScreen extends StatelessWidget {
  const TrackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Workouts'),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(spacingXl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CustomAppColors.primaryButtonLight,
                    CustomAppColors.primaryButtonLight.withOpacity(0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.directions_run,
                    size: 48,
                    color: CustomAppColors.white,
                  ),
                  const SizedBox(height: spacingMd),
                  const Text(
                    'Ready to Track?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: CustomAppColors.white,
                    ),
                  ),
                  const SizedBox(height: spacingSm),
                  Text(
                    'Track your runs, walks, and bike rides with GPS precision.',
                    style: TextStyle(
                      fontSize: 16,
                      color: CustomAppColors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: spacingLg),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LiveTrackingScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CustomAppColors.white,
                      foregroundColor: CustomAppColors.primaryButtonLight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingXl,
                        vertical: spacingMd,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(radiusMd),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow),
                        SizedBox(width: spacingSm),
                        Text(
                          'Start Tracking',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: spacingXl),

            // Quick Stats or Recent Activities (placeholder for now)
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: spacingLg),

            Row(
              children: [
                Expanded(
                  child: buildQuickActionCard(
                    context: context,
                    title: 'Running',
                    description: 'Start a run',
                    icon: Icons.directions_run,
                    color: CustomAppColors.progressGreen,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LiveTrackingScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: spacingMd),
                Expanded(
                  child: buildQuickActionCard(
                    context: context,
                    title: 'Walking',
                    description: 'Start a walk',
                    icon: Icons.directions_walk,
                    color: CustomAppColors.statusInfo,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LiveTrackingScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: spacingMd),

            Row(
              children: [
                Expanded(
                  child: buildQuickActionCard(
                    context: context,
                    title: 'Cycling',
                    description: 'Start cycling',
                    icon: Icons.directions_bike,
                    color: CustomAppColors.statusWarning,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LiveTrackingScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: spacingMd),
                Expanded(
                  child: buildQuickActionCard(
                    context: context,
                    title: 'Hiking',
                    description: 'Start hiking',
                    icon: Icons.terrain,
                    color: CustomAppColors.primary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LiveTrackingScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
