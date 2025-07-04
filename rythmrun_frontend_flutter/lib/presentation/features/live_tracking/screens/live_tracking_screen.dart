import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/workout_type_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

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

    // Use the LocationServiceStatus from state, fallback to permissionDenied
    final locationStatus =
        workoutState.locationServiceStatus ??
        LocationServiceStatus.permissionDenied;

    // Used LocationErrorHandler utility for consistent error handling
    final title = LocationErrorHandler.getErrorTitle(locationStatus);
    final buttonText = LocationErrorHandler.getActionText(locationStatus);
    final IconData icon =
        LocationErrorHandler.isLocationServicesDisabled(locationStatus)
            ? locationDisabledIcon
            : locationOffIcon;
    final String description =
        LocationErrorHandler.isLocationServicesDisabled(locationStatus)
            ? 'Location services are turned off on your device. Please enable them in device settings to track workouts.'
            : 'RythmRun needs location access to track your workouts with GPS precision.';
    final Color color =
        LocationErrorHandler.isLocationServicesDisabled(locationStatus)
            ? CustomAppColors.statusDanger
            : CustomAppColors.statusWarning;

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
            const SizedBox(height: spacingSm),
            Container(
              padding: const EdgeInsets.all(spacingSm),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(radiusSm),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                LocationErrorHandler.getLocationErrorMessage(locationStatus),
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: spacingLg),
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
                    ? settingsIcon
                    : locationOnIcon,
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
            buildWorkoutTypeCard(
              context: context,
              icon: runningIcon,
              title: 'Running',
              type: WorkoutType.running,
              onTap: () => notifier.startWorkout(WorkoutType.running),
            ),
            buildWorkoutTypeCard(
              context: context,
              icon: walkingIcon,
              title: 'Walking',
              type: WorkoutType.walking,
              onTap: () => notifier.startWorkout(WorkoutType.walking),
            ),
            buildWorkoutTypeCard(
              context: context,
              icon: cyclingIcon,
              title: 'Cycling',
              type: WorkoutType.cycling,
              onTap: () => notifier.startWorkout(WorkoutType.cycling),
            ),
            buildWorkoutTypeCard(
              context: context,
              icon: hikingIcon,
              title: 'Hiking',
              type: WorkoutType.hiking,
              onTap: () => notifier.startWorkout(WorkoutType.hiking),
            ),
          ],
        ),
      ],
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
            color: CustomAppColors.black.withOpacity(0.1),
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
                icon: distanceIcon,
              ),
              Container(width: 1, height: 40, color: CustomAppColors.border),
              _buildMetricColumn(
                label: 'Pace',
                value: state.formattedPace,
                icon: speedIcon,
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
            icon: pauseIcon,
            label: 'Pause',
            color: CustomAppColors.statusWarning,
            onPressed: () => notifier.pauseWorkout(),
          )
        else if (state.isPaused)
          _buildControlButton(
            icon: playArrowIcon,
            label: 'Resume',
            color: CustomAppColors.statusSuccess,
            onPressed: () => notifier.resumeWorkout(),
          ),

        // Stop Button
        _buildControlButton(
          icon: stopIcon,
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
            const Icon(errorOutlineIcon, color: CustomAppColors.statusDanger),
            const SizedBox(width: spacingMd),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: CustomAppColors.statusDanger),
              ),
            ),
            IconButton(
              onPressed: () => notifier.clearError(),
              icon: const Icon(closeIcon, color: CustomAppColors.statusDanger),
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
