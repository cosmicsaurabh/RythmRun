import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../../domain/entities/workout_session_entity.dart';
import '../providers/live_tracking_provider.dart';
import '../models/live_tracking_state.dart';
import '../../tracking_history/providers/tracking_history_provider.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveTrackingProvider.notifier).checkPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final liveTrackingState = ref.watch(liveTrackingProvider);
    final liveTrackingNotifier = ref.read(liveTrackingProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        backgroundColor: CustomAppColors.surfaceBackgroundDark,
        foregroundColor: CustomAppColors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(spacingLg),
          child: Column(
            children: [
              // Permission Status
              if (!liveTrackingState.hasLocationPermission)
                _buildPermissionCard(liveTrackingNotifier),

              if (liveTrackingState.hasLocationPermission) ...[
                // Workout Type Selection (if no active session)
                if (!liveTrackingState.hasActiveSession)
                  _buildWorkoutTypeSelection(liveTrackingNotifier),

                // Active Workout Display
                if (liveTrackingState.hasActiveSession) ...[
                  _buildWorkoutMetrics(liveTrackingState),
                  const SizedBox(height: spacingXl),
                  _buildWorkoutControls(
                    liveTrackingState,
                    liveTrackingNotifier,
                  ),
                ],
              ],

              // Error Display
              if (liveTrackingState.errorMessage != null)
                _buildErrorCard(
                  liveTrackingState.errorMessage!,
                  liveTrackingNotifier,
                ),

              // Loading Indicator
              if (liveTrackingState.isLoading)
                const Padding(
                  padding: EdgeInsets.all(spacingLg),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard(LiveTrackingNotifier notifier) {
    final workoutState = ref.watch(liveTrackingProvider);

    // Determine the type of issue based on error message
    bool isLocationServicesDisabled =
        workoutState.errorMessage?.contains('Location services are disabled') ??
        false;
    bool isPermissionDenied =
        workoutState.errorMessage?.contains('permission') ?? false;

    IconData icon;
    String title;
    String description;
    String buttonText;
    Color color;

    if (isLocationServicesDisabled) {
      icon = Icons.location_disabled;
      title = 'Location Services Disabled';
      description =
          'Location services are turned off on your device. Please enable them in device settings to track workouts.';
      buttonText = 'Open Settings';
      color = CustomAppColors.statusDanger;
    } else {
      icon = Icons.location_off;
      title = 'Location Permission Required';
      description =
          'RythmRun needs location access to track your workouts with GPS precision.';
      buttonText = 'Grant Permission';
      color = CustomAppColors.statusWarning;
    }

    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: spacingMd),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: spacingSm),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CustomAppColors.secondaryText),
            ),
            if (workoutState.errorMessage != null) ...[
              const SizedBox(height: spacingSm),
              Container(
                padding: const EdgeInsets.all(spacingSm),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(radiusSm),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  workoutState.errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: spacingLg),
            ElevatedButton.icon(
              onPressed: () {
                if (isLocationServicesDisabled) {
                  _showLocationSettingsDialog();
                } else {
                  notifier.checkPermissions();
                }
              },
              icon: Icon(
                isLocationServicesDisabled ? Icons.settings : Icons.location_on,
              ),
              label: Text(buttonText),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: CustomAppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutTypeSelection(LiveTrackingNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Workout Type',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: spacingLg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: spacingMd,
          mainAxisSpacing: spacingMd,
          childAspectRatio: 1.2,
          children: [
            _buildWorkoutTypeCard(
              icon: Icons.directions_run,
              title: 'Running',
              type: WorkoutType.running,
              onTap: () => notifier.startWorkout(WorkoutType.running),
            ),
            _buildWorkoutTypeCard(
              icon: Icons.directions_walk,
              title: 'Walking',
              type: WorkoutType.walking,
              onTap: () => notifier.startWorkout(WorkoutType.walking),
            ),
            _buildWorkoutTypeCard(
              icon: Icons.directions_bike,
              title: 'Cycling',
              type: WorkoutType.cycling,
              onTap: () => notifier.startWorkout(WorkoutType.cycling),
            ),
            _buildWorkoutTypeCard(
              icon: Icons.terrain,
              title: 'Hiking',
              type: WorkoutType.hiking,
              onTap: () => notifier.startWorkout(WorkoutType.hiking),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkoutTypeCard({
    required IconData icon,
    required String title,
    required WorkoutType type,
    required VoidCallback onTap,
  }) {
    return Card(
      color: CustomAppColors.primaryButtonLight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(spacingLg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: CustomAppColors.white),
              const SizedBox(height: spacingSm),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CustomAppColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkoutMetrics(LiveTrackingState state) {
    return Container(
      padding: const EdgeInsets.all(spacingXl),
      decoration: BoxDecoration(
        color: CustomAppColors.surfaceBackgroundLight,
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Workout Type
          Text(
            state.currentSession!.type.name.toUpperCase(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: CustomAppColors.secondaryText,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: spacingLg),

          // Time
          Text(
            state.formattedElapsedTime,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: CustomAppColors.primaryTextDark,
            ),
          ),
          const SizedBox(height: spacingLg),

          // Distance and Pace Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMetricColumn(
                label: 'Distance',
                value: state.formattedDistance,
                icon: Icons.straighten,
              ),
              Container(width: 1, height: 40, color: CustomAppColors.border),
              _buildMetricColumn(
                label: 'Pace',
                value: state.formattedPace,
                icon: Icons.speed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: CustomAppColors.primaryButtonLight, size: 24),
        const SizedBox(height: spacingSm),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: CustomAppColors.secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: spacingXs),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: CustomAppColors.primaryTextDark,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutControls(
    LiveTrackingState state,
    LiveTrackingNotifier notifier,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Pause/Resume Button
        if (state.isTracking)
          _buildControlButton(
            icon: Icons.pause,
            label: 'Pause',
            color: CustomAppColors.statusWarning,
            onPressed: () => notifier.pauseWorkout(),
          )
        else if (state.isPaused)
          _buildControlButton(
            icon: Icons.play_arrow,
            label: 'Resume',
            color: CustomAppColors.statusSuccess,
            onPressed: () => notifier.resumeWorkout(),
          ),

        // Stop Button
        _buildControlButton(
          icon: Icons.stop,
          label: 'Finish',
          color: CustomAppColors.statusDanger,
          onPressed: () => _showStopConfirmation(notifier),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: CustomAppColors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingXl,
          vertical: spacingLg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: spacingXs),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message, LiveTrackingNotifier notifier) {
    return Card(
      color: CustomAppColors.statusDanger.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(spacingLg),
        child: Row(
          children: [
            const Icon(Icons.error, color: CustomAppColors.statusDanger),
            const SizedBox(width: spacingMd),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: CustomAppColors.statusDanger),
              ),
            ),
            IconButton(
              onPressed: () => notifier.clearError(),
              icon: const Icon(
                Icons.close,
                color: CustomAppColors.statusDanger,
              ),
            ),
          ],
        ),
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
                  Navigator.pop(context); // Close dialog
                  await notifier.stopWorkout();

                  // Refresh workouts list to show the new workout
                  ref.read(trackingHistoryProvider.notifier).refresh();

                  if (context.mounted) {
                    Navigator.pop(context); // Return to previous screen
                  }
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
                onPressed: () {
                  Navigator.pop(context);
                  // Note: Opening system settings programmatically requires additional permissions
                  // For now, we'll just show instructions
                },
                child: const Text('Got it'),
              ),
            ],
          ),
    );
  }
}
