import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({super.key});

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen>
    with TickerProviderStateMixin {
  late AnimationController _cardAnimationController;
  late Animation<double> _cardAnimation;
  bool _isCardExpanded = false;

  @override
  void initState() {
    super.initState();
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _cardAnimationController.dispose();
    super.dispose();
  }

  void _startWorkout(
    BuildContext context,
    WidgetRef ref,
    WorkoutType workoutType,
  ) async {
    final liveTrackingNotifier = ref.read(liveTrackingProvider.notifier);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting ${workoutType.name} workout...'),
        duration: const Duration(seconds: 2),
        backgroundColor: CustomAppColors.statusSuccess,
      ),
    );
    _collapseCard();

    // Start the workout
    await liveTrackingNotifier.startWorkout(workoutType);
  }

  void _onStartTrackingPressed() {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final liveTrackingNotifier = ref.read(liveTrackingProvider.notifier);

    if (!liveTrackingState.hasLocationPermission) {
      // Check permissions first
      liveTrackingNotifier.checkPermissions();
    }

    // Expand the card regardless
    setState(() {
      _isCardExpanded = true;
    });
    _cardAnimationController.forward();
  }

  void _collapseCard() {
    setState(() {
      _isCardExpanded = false;
    });
    _cardAnimationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final liveTrackingState = ref.watch(liveTrackingProvider);
        final liveTrackingNotifier = ref.read(liveTrackingProvider.notifier);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Track Workouts'),
            automaticallyImplyLeading: false,
            elevation: 0,
            actions:
                _isCardExpanded
                    ? [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _collapseCard,
                      ),
                    ]
                    : null,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Animated Tracking Card
              Padding(
                padding: const EdgeInsets.only(
                  left: spacingLg,
                  right: spacingLg,
                ),
                child: AnimatedBuilder(
                  animation: _cardAnimation,
                  builder: (context, child) {
                    return Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(spacingXl),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(radiusLg),
                      ),
                      child:
                          liveTrackingState.hasActiveSession
                              ? _buildActiveWorkoutContent(
                                liveTrackingState,
                                liveTrackingNotifier,
                              )
                              : _isCardExpanded
                              ? _buildExpandedContent(
                                liveTrackingState,
                                liveTrackingNotifier,
                              )
                              : _buildCollapsedContent(liveTrackingState),
                    );
                  },
                ),
              ),
              // const SizedBox(height: spacingLg),
              if (liveTrackingState.isLoading)
                const Padding(
                  padding: EdgeInsets.all(spacingLg),
                  child: CircularProgressIndicator(),
                ),
              if (liveTrackingState.errorMessage != null)
                Text(liveTrackingState.errorMessage!),

              const LiveMapFeed(),

              // Quick Actions (hidden when card is expanded)
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollapsedContent(LiveTrackingState liveTrackingState) {
    return Column(
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
          style: TextStyle(fontSize: 16, color: CustomAppColors.secondaryText),
        ),
        const SizedBox(height: spacingLg),
        ElevatedButton(
          onPressed: _onStartTrackingPressed,
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedContent(
    LiveTrackingState liveTrackingState,
    LiveTrackingNotifier liveTrackingNotifier,
  ) {
    if (!liveTrackingState.hasLocationPermission) {
      return _buildPermissionContent(liveTrackingNotifier, liveTrackingState);
    }

    return _buildWorkoutTypeSelection(liveTrackingNotifier);
  }

  Widget _buildPermissionContent(
    LiveTrackingNotifier notifier,
    LiveTrackingState workoutState,
  ) {
    final locationStatus =
        workoutState.locationServiceStatus ??
        LocationServiceStatus.permissionDenied;

    final title = LocationErrorHandler.getErrorTitle(locationStatus);
    final buttonText = LocationErrorHandler.getActionText(locationStatus);
    final IconData icon =
        LocationErrorHandler.isLocationServicesDisabled(locationStatus)
            ? Icons.location_disabled
            : Icons.location_off;
    final String description =
        LocationErrorHandler.isLocationServicesDisabled(locationStatus)
            ? 'Location services are turned off on your device. Please enable them in device settings to track workouts.'
            : 'RythmRun needs location access to track your workouts with GPS precision.';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: Theme.of(context).colorScheme.onPrimary),
        const SizedBox(height: spacingLg),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: spacingMd),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: spacingXl),
        ElevatedButton.icon(
          onPressed: () {
            if (LocationErrorHandler.isLocationServicesDisabled(
              locationStatus,
            )) {
              _showLocationSettingsDialog();
            } else {
              notifier.checkPermissions();
            }
          },
          icon: Icon(
            LocationErrorHandler.isLocationServicesDisabled(locationStatus)
                ? Icons.settings
                : Icons.location_on,
          ),
          label: Text(buttonText),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.onPrimary,
            foregroundColor: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(
              horizontal: spacingXl,
              vertical: spacingMd,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutTypeSelection(LiveTrackingNotifier notifier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Choose Workout Type',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(height: spacingLg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: spacingSm,
          mainAxisSpacing: spacingSm,
          childAspectRatio: 1.6,
          children: [
            _buildWorkoutTypeCard(
              icon: Icons.directions_run,
              title: 'Running',
              onTap: () => _startWorkout(context, ref, WorkoutType.running),
            ),
            _buildWorkoutTypeCard(
              icon: Icons.directions_walk,
              title: 'Walking',
              onTap: () => _startWorkout(context, ref, WorkoutType.walking),
            ),
            _buildWorkoutTypeCard(
              icon: Icons.directions_bike,
              title: 'Cycling',
              onTap: () => _startWorkout(context, ref, WorkoutType.cycling),
            ),
            _buildWorkoutTypeCard(
              icon: Icons.terrain,
              title: 'Hiking',
              onTap: () => _startWorkout(context, ref, WorkoutType.hiking),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkoutTypeCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(spacingMd),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              const SizedBox(height: spacingSm),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveWorkoutContent(
    LiveTrackingState state,
    LiveTrackingNotifier notifier,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Workout Type
        Text(
          state.currentSession!.type.name.toUpperCase(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: spacingSm),

        // Time
        Text(
          state.formattedElapsedTime,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(height: spacingSm),

        // Distance and Pace
        Row(
          // mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _buildMetricColumn(
                label: 'Distance',
                value: state.formattedDistance,
                icon: Icons.straighten,
              ),
            ),
            Container(
              width: 1,
              height: 30,
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.3),
            ),
            Expanded(
              child: _buildMetricColumn(
                label: 'Pace',
                value: state.formattedPace,
                icon: Icons.speed,
              ),
            ),
          ],
        ),
        const SizedBox(height: spacingSm),

        // Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (state.isTracking)
              _buildControlButton(
                icon: Icons.pause,
                label: 'Pause',
                onPressed: () => notifier.pauseWorkout(),
              )
            else if (state.isPaused)
              _buildControlButton(
                icon: Icons.play_arrow,
                label: 'Resume',
                onPressed: () => notifier.resumeWorkout(),
              ),
            _buildControlButton(
              icon: Icons.stop,
              label: 'Finish',
              onPressed: () => _showStopConfirmation(notifier),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricColumn({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 24),
        // const SizedBox(height: spacingSm),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
        // const SizedBox(height: spacingSm),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
        foregroundColor: Theme.of(context).colorScheme.primary,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingLg,
          vertical: spacingSm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: spacingXs),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showStopConfirmation(LiveTrackingNotifier notifier) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Finish Workout?'),
            content: const Text(
              'Are you sure you want to finish this workout? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await notifier.stopWorkout();
                  ref.read(trackingHistoryProvider.notifier).refresh();
                  _collapseCard();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: CustomAppColors.statusDanger,
                ),
                child: const Text('Finish'),
              ),
            ],
          ),
    );
  }

  void _showLocationSettingsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Enable Location Services'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To track your workouts, please enable location services:',
                ),
                SizedBox(height: 12),
                Text('1. Open your device Settings'),
                Text('2. Go to Privacy & Security'),
                Text('3. Tap Location Services'),
                Text('4. Turn on Location Services'),
                Text('5. Return to RythmRun and try again'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
    );
  }
}
