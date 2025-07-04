import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/quick_action_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/screens/live_tracking_screen.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class TrackScreen extends ConsumerWidget {
  const TrackScreen({super.key});

  void _startWorkoutAndNavigate(
    BuildContext context,
    WidgetRef ref,
    WorkoutType workoutType,
  ) async {
    final liveTrackingNotifier = ref.read(liveTrackingProvider.notifier);

    // Show notification that workout is starting
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting ${workoutType.name} workout...'),
        duration: const Duration(seconds: 2),
        backgroundColor: CustomAppColors.statusSuccess,
      ),
    );

    // Start the workout
    await liveTrackingNotifier.startWorkout(workoutType);

    // Navigate to live tracking screen
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const LiveTrackingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  // colors: [CustomAppColors.colorA, CustomAppColors.colorB],
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    runningIcon,
                    size: 48,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(height: spacingMd),
                  Text(
                    'Ready to Track?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: spacingSm),
                  Text(
                    'Track your runs, walks, and bike rides with GPS precision.',
                    style: TextStyle(
                      fontSize: 16,
                      color: CustomAppColors.secondaryText,
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
                      backgroundColor: Theme.of(context).colorScheme.onPrimary,
                      foregroundColor: Theme.of(context).colorScheme.primary,
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
                        Icon(playArrowIcon),
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
                    icon: runningIcon,
                    color: CustomAppColors.running,
                    onTap:
                        () => _startWorkoutAndNavigate(
                          context,
                          ref,
                          WorkoutType.running,
                        ),
                  ),
                ),
                const SizedBox(width: spacingMd),
                Expanded(
                  child: buildQuickActionCard(
                    context: context,
                    title: 'Walking',
                    description: 'Start a walk',
                    icon: walkingIcon,
                    color: CustomAppColors.walking,
                    onTap:
                        () => _startWorkoutAndNavigate(
                          context,
                          ref,
                          WorkoutType.walking,
                        ),
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
                    icon: cyclingIcon,
                    color: CustomAppColors.cycling,
                    onTap:
                        () => _startWorkoutAndNavigate(
                          context,
                          ref,
                          WorkoutType.cycling,
                        ),
                  ),
                ),
                const SizedBox(width: spacingMd),
                Expanded(
                  child: buildQuickActionCard(
                    context: context,
                    title: 'Hiking',
                    description: 'Start hiking',
                    icon: hikingIcon,
                    color: CustomAppColors.hiking,
                    onTap:
                        () => _startWorkoutAndNavigate(
                          context,
                          ref,
                          WorkoutType.hiking,
                        ),
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
