import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/quick_action_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed_helper.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_details_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/screens/workout_history_map_viewer.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class TrackingHistoryDetailsScreen extends ConsumerStatefulWidget {
  final WorkoutSessionEntity workout;

  const TrackingHistoryDetailsScreen({super.key, required this.workout});

  @override
  ConsumerState<TrackingHistoryDetailsScreen> createState() =>
      _TrackingHistoryDetailsScreenState();
}

class _TrackingHistoryDetailsScreenState
    extends ConsumerState<TrackingHistoryDetailsScreen> {
  final bool _showMapTiles = true;

  @override
  void initState() {
    super.initState();
    // Load full workout details on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.workout.id != null) {
        ref
            .read(trackingHistoryDetailsProvider.notifier)
            .loadWorkoutDetails(widget.workout.id!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingHistoryDetailsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Workout Details',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios),
        ),
      ),
      body: SafeArea(
        child:
            state.isLoading
                ? Center(child: CupertinoActivityIndicator())
                : state.errorMessage != null
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: CustomAppColors.statusError,
                      ),
                      SizedBox(height: spacingMd),
                      Text(
                        state.errorMessage ?? 'Something went wrong',
                        style: TextStyle(color: CustomAppColors.statusError),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: spacingMd),
                      ElevatedButton(
                        onPressed: () {
                          if (widget.workout.id != null) {
                            ref
                                .read(trackingHistoryDetailsProvider.notifier)
                                .loadWorkoutDetails(widget.workout.id!);
                          }
                        },
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
                : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Map view with improved styling
                      Container(
                        margin: const EdgeInsets.all(spacingMd),
                        height: 380,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radiusLg),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radiusXl),
                          child: WorkoutHistoryMapViewer(
                            workout: state.workout ?? widget.workout,
                            showMapTiles: _showMapTiles,
                            showControls: true,
                          ),
                        ),
                      ),

                      const SizedBox(height: spacingMd),

                      // Enhanced stats section
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: spacingMd,
                        ),
                        child: _buildComprehensiveStats(
                          state.workout ?? widget.workout,
                        ),
                      ),

                      const SizedBox(height: spacingLg),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildComprehensiveStats(WorkoutSessionEntity workout) {
    final duration =
        workout.endTime != null && workout.startTime != null
            ? workout.endTime!.difference(workout.startTime!)
            : Duration.zero;

    final activeDuration = workout.activeDuration ?? duration;
    final totalDuration =
        activeDuration + (workout.pausedDuration ?? Duration.zero);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Workout Header
        _buildWorkoutHeader(workout),

        const SizedBox(height: spacingLg),

        // Performance Metrics
        _buildPerformanceSection(workout, totalDuration, activeDuration),

        const SizedBox(height: spacingLg),

        // Session Timeline
        _buildSessionTimeline(workout),

        // Additional Metrics (if available)
        if (_hasAdditionalMetrics(workout)) ...[
          const SizedBox(height: spacingLg),
          _buildAdditionalMetrics(workout),
        ],

        // Notes (if available)
        if (workout.notes != null && workout.notes!.isNotEmpty) ...[
          const SizedBox(height: spacingLg),
          _buildNotesSection(workout),
        ],
      ],
    );
  }

  Widget _buildWorkoutHeader(WorkoutSessionEntity workout) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            getWorkoutColor(workout.type).withOpacity(0.1),
            getWorkoutColor(workout.type).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(
          color: getWorkoutColor(workout.type).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(spacingMd),
            decoration: BoxDecoration(
              color: getWorkoutColor(workout.type),
              borderRadius: BorderRadius.circular(radiusMd),
              boxShadow: [
                BoxShadow(
                  color: getWorkoutColor(workout.type).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              getWorkoutIcon(workout.type),
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getWorkoutTypeString(workout.type),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: getWorkoutColor(workout.type),
                  ),
                ),
                const SizedBox(height: spacingSm),
                Text(
                  _formatFullDate(workout.startTime),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: CustomAppColors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection(
    WorkoutSessionEntity workout,
    Duration totalDuration,
    Duration activeDuration,
  ) {
    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: Theme.of(context).colorScheme.onSurface,
                size: 20,
              ),
              const SizedBox(width: spacingSm),
              Text(
                'Performance Metrics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: CustomAppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingLg),
          Row(
            children: [
              Expanded(
                child: buildQuickActionCard(
                  context: context,
                  icon: distanceIcon,
                  value:
                      '${(workout.totalDistance / 1000).toStringAsFixed(2)} km',
                  title: 'Distance',
                  color: CustomAppColors.distance,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: spacingMd),
              Expanded(
                child: buildQuickActionCard(
                  context: context,
                  icon: speedIcon,
                  value: _formatPace(workout.averagePace),
                  title: 'Avg Pace',
                  color: CustomAppColors.colorA,
                  onTap: () {},
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
                  icon: timeIcon,
                  value: _formatDuration(totalDuration),
                  title: 'Total Time',
                  color: CustomAppColors.time,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: spacingMd),
              Expanded(
                child: buildQuickActionCard(
                  context: context,
                  icon: activeIcon,
                  value: _formatDuration(activeDuration),
                  title: 'Active Time',
                  color: CustomAppColors.colorB,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTimeline(WorkoutSessionEntity workout) {
    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(timeIcon, color: CustomAppColors.secondaryText, size: 20),
              const SizedBox(width: spacingSm),
              Text(
                'Session Timeline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: CustomAppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingLg),
          Row(
            children: [
              Expanded(
                child: _buildDetailRow(
                  'Started',
                  _formatTime(workout.startTime),
                  startIcon,
                  CustomAppColors.statusSuccess,
                ),
              ),
              Container(
                width: 2,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      CustomAppColors.statusSuccess,
                      CustomAppColors.statusError,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
                margin: const EdgeInsets.symmetric(horizontal: spacingMd),
              ),
              Expanded(
                child: _buildDetailRow(
                  'Ended',
                  _formatTime(workout.endTime),
                  stopIcon,
                  CustomAppColors.statusError,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasAdditionalMetrics(WorkoutSessionEntity workout) {
    return (workout.elevationGain != null && workout.elevationGain! > 0) ||
        workout.calories != null;
  }

  Widget _buildAdditionalMetrics(WorkoutSessionEntity workout) {
    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                insightsIcon,
                color: CustomAppColors.secondaryText,
                size: 20,
              ),
              const SizedBox(width: spacingSm),
              Text(
                'Additional Metrics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: CustomAppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingLg),
          Row(
            children: [
              if (workout.elevationGain != null &&
                  workout.elevationGain! > 0) ...[
                Expanded(
                  child: _buildDetailRow(
                    'Elevation Gain',
                    '${workout.elevationGain!.toInt()}m',
                    elevationIcon,
                    CustomAppColors.statusSuccess,
                  ),
                ),
              ],
              if (_hasAdditionalMetrics(workout) &&
                  workout.elevationGain != null &&
                  workout.elevationGain! > 0 &&
                  workout.calories != null) ...[
                Container(
                  width: 2,
                  height: 50,
                  color: Colors.grey[300],
                  margin: const EdgeInsets.symmetric(horizontal: spacingMd),
                ),
              ],
              if (workout.calories != null) ...[
                Expanded(
                  child: _buildDetailRow(
                    'Calories Burned',
                    '${workout.calories}',
                    caloriesIcon,
                    CustomAppColors.statusWarning,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(WorkoutSessionEntity workout) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(
          color: CustomAppColors.secondaryText.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(notesIcon, size: 20, color: CustomAppColors.secondaryText),
              const SizedBox(width: spacingSm),
              Text(
                'Workout Notes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: CustomAppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(spacingMd),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(radiusMd),
              border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
            child: Text(
              workout.notes!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CustomAppColors.secondaryText,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return 'N/A';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime? date) {
    if (date == null) return 'Unknown date';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
    // if (dateOnly == today) {
    //   return 'Today at ${_formatTime(date)}';
    // } else if (dateOnly == yesterday) {
    //   return 'Yesterday at ${_formatTime(date)}';
    // } else {
    //   return '${date.day}/${date.month}/${date.year} at ${_formatTime(date)}';
    // }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _formatPace(double? pace) {
    if (pace == null || pace == 0) return '--:--';
    final minutes = pace.floor();
    final seconds = ((pace - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
  }

  String _getWorkoutTypeString(WorkoutType type) {
    return type.name[0].toUpperCase() + type.name.substring(1);
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(spacingSm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
