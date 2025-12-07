import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';
import 'package:rythmrun_frontend_flutter/features/ads/presentation/banner_ad_widget.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_providers.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed.dart';
import 'package:rythmrun_frontend_flutter/presentation/shared/widgets/connectivity_badge.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({super.key});

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen>
    with TickerProviderStateMixin {
  late AnimationController _cardAnimationController;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;
  bool _isCardExpanded = false;
  bool _isActiveWorkoutExpanded = false;

  @override
  void initState() {
    super.initState();
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardAnimationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardAnimationController,
        curve: Curves.easeOutCubic,
      ),
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

    // Expand the card
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
        final sessionState = ref.watch(sessionStateProvider);
        final isOffline = ref.watch(isOfflineModeProvider);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Track Workouts'),
            automaticallyImplyLeading: false,
            elevation: 0,
            actions: const [ConnectivityBadge(), SizedBox(width: spacingMd)],
          ),
          bottomNavigationBar: const ActivityBannerAdSlot(),
          body: Stack(
            // crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text('Session State: ${sessionState.name}'),
                  Text('Is Offline: $isOffline'),
                  Text('Expected: authenticatedOffline when backend down'),
                ],
              ),
              const LiveMapFeed(),
              // Animated Tracking Card
              Positioned(
                top: spacingLg,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: spacingLg,
                    right: spacingLg,
                  ),
                  child: AnimatedBuilder(
                    animation: _cardAnimationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isCardExpanded ? _scaleAnimation.value : 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                offset: const Offset(0, 8),
                                blurRadius: 16,
                                spreadRadius: -2,
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                offset: const Offset(0, 4),
                                blurRadius: 8,
                                spreadRadius: -1,
                              ),
                            ],
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.75),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(radiusXl),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(radiusXl),
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOutCubic,
                              child: Opacity(
                                opacity:
                                    _isCardExpanded
                                        ? _opacityAnimation.value
                                        : 1.0,
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    _isCardExpanded ? spacingXl : spacingLg,
                                  ),
                                  child: _buildCardContent(
                                    liveTrackingState,
                                    liveTrackingNotifier,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (liveTrackingState.isLoading)
                Positioned(
                  top: spacingLg,
                  left: spacingLg,
                  right: spacingLg,
                  child: const Padding(
                    padding: EdgeInsets.all(spacingLg),
                    child: CupertinoActivityIndicator(),
                  ),
                ),

              // Quick Actions (hidden when card is expanded)
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardContent(
    LiveTrackingState liveTrackingState,
    LiveTrackingNotifier liveTrackingNotifier,
  ) {
    if (liveTrackingState.hasActiveSession) {
      return _buildActiveWorkoutContent(
        liveTrackingState,
        liveTrackingNotifier,
      );
    }

    if (_isCardExpanded) {
      return _buildExpandedContent(liveTrackingState, liveTrackingNotifier);
    }

    return _buildCollapsedContent(liveTrackingState);
  }

  Widget _buildCollapsedContent(LiveTrackingState liveTrackingState) {
    return InkWell(
      onTap: _onStartTrackingPressed,
      borderRadius: BorderRadius.circular(radiusXl),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(spacingMd),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            child: Icon(
              runningIcon,
              size: 32,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ready to Track?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: spacingXs),
                Text(
                  'Tap to start your workout',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 20,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
    LiveTrackingState liveTrackingState,
    LiveTrackingNotifier liveTrackingNotifier,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        GestureDetector(
          onTap: _collapseCard,
          child: Container(
            margin: const EdgeInsets.only(bottom: spacingMd),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (!liveTrackingState.hasLocationPermission)
          _buildPermissionContent(liveTrackingNotifier, liveTrackingState)
        else
          _buildWorkoutTypeSelection(liveTrackingNotifier),
      ],
    );
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
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(spacingLg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 56,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
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
            fontSize: 15,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.85),
            height: 1.4,
          ),
        ),
        const SizedBox(height: spacingXl),
        ElevatedButton.icon(
          onPressed: () async {
            if (LocationErrorHandler.isLocationServicesDisabled(
              locationStatus,
            )) {
              // On Android: shows system dialog with "Turn on" button
              // On iOS: opens location settings
              await notifier.requestLocationService();
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusLg),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutTypeSelection(LiveTrackingNotifier notifier) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: spacingMd,
          mainAxisSpacing: spacingMd,
          childAspectRatio: 1.5,
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
    return Material(
      color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.25),
      borderRadius: BorderRadius.circular(radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusLg),
        child: Container(
          padding: const EdgeInsets.all(spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radiusLg),
            border: Border.all(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(spacingSm),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(radiusMd),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: spacingSm),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Header with expand/collapse button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Workout Type
              Text(
                state.currentSession!.type.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withOpacity(0.8),
                  letterSpacing: 1.0,
                ),
              ),
              // Expand/Collapse button
              IconButton(
                icon: Icon(
                  _isActiveWorkoutExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: () {
                  setState(() {
                    _isActiveWorkoutExpanded = !_isActiveWorkoutExpanded;
                  });
                },
                tooltip: _isActiveWorkoutExpanded ? 'Collapse' : 'Expand',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: spacingXs),

          // Collapsed view - always visible
          _buildCollapsedActiveWorkoutView(state),

          // Expanded view - shown when expanded
          if (_isActiveWorkoutExpanded) ...[
            const SizedBox(height: spacingMd),
            _buildExpandedActiveWorkoutView(state),
          ],

          const SizedBox(height: spacingXs),

          // Controls - always visible
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
      ),
    );
  }

  Widget _buildCollapsedActiveWorkoutView(LiveTrackingState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Time - more compact
        Expanded(
          child: Text(
            state.formattedElapsedTime,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        // Divider
        Container(
          width: 1,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: spacingMd),
          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.3),
        ),
        // Distance and Pace - compact horizontal layout
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactMetric(
                label: 'Distance',
                value: state.formattedDistance,
                icon: Icons.straighten,
              ),
              Container(
                width: 1,
                height: 20,
                color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
              ),
              _buildCompactMetric(
                label: 'Pace',
                value: state.formattedPace,
                icon: Icons.speed,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
            size: 18,
          ),
          const SizedBox(height: spacingXs),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedActiveWorkoutView(LiveTrackingState state) {
    final session = state.currentSession!;
    final hasElevation =
        session.elevationGain != null && session.elevationGain! > 0;
    final hasCalories = session.calories != null;
    final maxSpeedKmh =
        session.maxSpeed > 0
            ? (session.maxSpeed * 3.6).toStringAsFixed(1)
            : '0.0';

    return Container(
      padding: const EdgeInsets.all(spacingMd),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Additional metrics grid
          Row(
            children: [
              Expanded(
                child: _buildDetailMetric(
                  label: 'Avg Speed',
                  value: state.formattedAverageSpeed,
                  icon: Icons.trending_up,
                ),
              ),
              const SizedBox(width: spacingMd),
              Expanded(
                child: _buildDetailMetric(
                  label: 'Max Speed',
                  value: '$maxSpeedKmh km/h',
                  icon: Icons.speed,
                ),
              ),
            ],
          ),
          if (hasElevation || hasCalories) ...[
            const SizedBox(height: spacingMd),
            Row(
              children: [
                if (hasElevation)
                  Expanded(
                    child: _buildDetailMetric(
                      label: 'Elevation',
                      value: '${session.elevationGain!.toStringAsFixed(0)} m',
                      icon: Icons.terrain,
                    ),
                  ),
                if (hasElevation && hasCalories)
                  const SizedBox(width: spacingMd),
                if (hasCalories)
                  Expanded(
                    child: _buildDetailMetric(
                      label: 'Calories',
                      value: '${session.calories}',
                      icon: Icons.local_fire_department,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: spacingMd),
          // Session info
          Divider(
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
            height: 1,
          ),
          const SizedBox(height: spacingSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoRow(
                icon: Icons.access_time,
                label: 'Started',
                value: _formatTime(session.startTime),
              ),
              if (session.pausedDuration != null &&
                  session.pausedDuration!.inSeconds > 0)
                _buildInfoRow(
                  icon: Icons.pause_circle_outline,
                  label: 'Paused',
                  value: _formatDuration(session.pausedDuration!),
                ),
            ],
          ),
          const SizedBox(height: spacingXs),
          _buildInfoRow(
            icon: Icons.location_on,
            label: 'Points',
            value: '${session.trackingPoints.length}',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
            ),
            const SizedBox(width: spacingXs),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: spacingXs),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.6),
        ),
        const SizedBox(width: spacingXs),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
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
                  await _showPostActivityAd();
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

  Future<void> _showPostActivityAd() async {
    final adsService = ref.read(adsServiceProvider);
    final result = await adsService.showPostActivityAd();
    if (!mounted) return;

    if (result.status == AdsResultStatus.failed ||
        result.status == AdsResultStatus.unavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'No ad available right now.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
