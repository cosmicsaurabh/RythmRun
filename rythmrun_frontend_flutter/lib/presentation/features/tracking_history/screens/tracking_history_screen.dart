import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed_helper.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/screens/tracking_history_details_screen.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';
import '../providers/tracking_history_provider.dart';

class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsState = ref.watch(trackingHistoryProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, ref, workoutsState),
          _buildSliverBody(context, ref, workoutsState),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(.1),
                Theme.of(context).colorScheme.onPrimary.withOpacity(.1),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Workout History',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onBackground,
                            ),
                          ),
                          const SizedBox(height: spacingSm),
                          Text(
                            _getStatsText(state.workouts),
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color: CustomAppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      if (state.workouts.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(radiusMd),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(refreshIcon),
                            onPressed: () {
                              ref
                                  .read(trackingHistoryProvider.notifier)
                                  .refresh();
                            },
                            tooltip: 'Refresh workouts',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: spacingMd),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverBody(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    return SliverToBoxAdapter(child: _buildBody(context, ref, state));
  }

  String _getStatsText(List<WorkoutSessionEntity> workouts) {
    if (workouts.isEmpty) return 'No workouts yet';
    final totalTime = workouts.fold<Duration>(Duration.zero, (sum, workout) {
      final duration =
          workout.endTime != null && workout.startTime != null
              ? workout.endTime!.difference(workout.startTime!)
              : Duration.zero;
      return sum + duration;
    });
    final totalDistance = workouts.fold<double>(
      0,
      (sum, workout) => sum + workout.totalDistance,
    );
    final totalWorkouts = workouts.length;
    return '$totalWorkouts workouts • ${(totalDistance / 1000).toStringAsFixed(1)}km • ${_formatDuration(totalTime)}';
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    if (state.isLoading) {
      return _buildLoadingState();
    }

    if (state.errorMessage != null) {
      return _buildErrorState(context, ref, state.errorMessage!);
    }

    if (state.workouts.isEmpty) {
      return _buildEmptyState(context);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: spacingMd),
          _buildQuickStats(state.workouts),
          const SizedBox(height: spacingLg),
          _buildWorkoutsList(context, ref, state.workouts),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: spacingLg),
            Text(
              'Loading your workouts...',
              style: TextStyle(
                fontSize: 16,
                color: CustomAppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    String errorMessage,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(spacingLg),
              decoration: BoxDecoration(
                color: CustomAppColors.statusDanger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(radiusLg),
              ),
              child: Icon(
                errorOutlineIcon,
                size: 60,
                color: CustomAppColors.statusDanger,
              ),
            ),
            const SizedBox(height: spacingLg),
            Text(
              'Something went wrong',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: spacingSm),
            Text(
              errorMessage,
              style: TextStyle(color: CustomAppColors.secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: spacingLg),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(trackingHistoryProvider.notifier).refresh();
              },
              icon: const Icon(refreshIcon),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: spacingLg,
                  vertical: spacingMd,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(List<WorkoutSessionEntity> workouts) {
    return Builder(
      builder: (context) {
        final totalDistance = workouts.fold<double>(
          0,
          (sum, workout) => sum + workout.totalDistance,
        );
        final totalTime = workouts.fold<Duration>(Duration.zero, (
          sum,
          workout,
        ) {
          final duration =
              workout.endTime != null && workout.startTime != null
                  ? workout.endTime!.difference(workout.startTime!)
                  : Duration.zero;
          return sum + duration;
        });

        return Container(
          padding: const EdgeInsets.all(spacingLg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.primaryContainer.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(radiusLg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This Month',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: spacingMd),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickStatItem(
                      '${workouts.length}',
                      'Workouts',
                      Icons.fitness_center,
                      Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Expanded(
                    child: _buildQuickStatItem(
                      '${(totalDistance / 1000).toStringAsFixed(1)}km',
                      'Distance',
                      distanceIcon,
                      Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Expanded(
                    child: _buildQuickStatItem(
                      '${totalTime.inHours}h ${totalTime.inMinutes % 60}m',
                      'Time',
                      timeIcon,
                      Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStatItem(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: spacingSm),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
        ),
      ],
    );
  }

  Widget _buildWorkoutsList(
    BuildContext context,
    WidgetRef ref,
    List<WorkoutSessionEntity> workouts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: spacingMd),
        Text(
          'Recent Activities',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: workouts.length,
          separatorBuilder:
              (context, index) => const SizedBox(height: spacingMd),
          itemBuilder: (context, index) {
            final workout = workouts[index];
            return _buildWorkoutCard(context, ref, workout);
          },
        ),
        const SizedBox(height: spacingXl),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(spacingXl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CustomAppColors.running.withOpacity(0.1),
                    CustomAppColors.cycling.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(radiusXl),
                border: Border.all(
                  color: CustomAppColors.running.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(runningIcon, size: 80, color: CustomAppColors.running),
                  const SizedBox(height: spacingMd),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        walkingIcon,
                        size: iconSizeMd,
                        color: CustomAppColors.walking,
                      ),
                      const SizedBox(width: spacingSm),
                      Icon(
                        cyclingIcon,
                        size: iconSizeMd,
                        color: CustomAppColors.cycling,
                      ),
                      const SizedBox(width: spacingSm),
                      Icon(
                        hikingIcon,
                        size: iconSizeMd,
                        color: CustomAppColors.hiking,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: spacingLg),
            Text(
              'No Activities Yet',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: CustomAppColors.secondaryText,
              ),
            ),
            const SizedBox(height: spacingSm),
            Text(
              'Start your fitness journey today!\nTrack your runs, walks, bike rides, and hikes.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: CustomAppColors.secondaryText,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: spacingLg),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingLg,
                vertical: spacingMd,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [CustomAppColors.running, CustomAppColors.cycling],
                ),
                borderRadius: BorderRadius.circular(radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: CustomAppColors.running.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(radiusLg),
                child: InkWell(
                  onTap: () {
                    //  tab change to 0
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(addIcon, color: Colors.white, size: iconSizeSm),
                      const SizedBox(width: spacingSm),
                      Text(
                        'Start Your First Workout',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutCard(
    BuildContext context,
    WidgetRef ref,
    WorkoutSessionEntity workout,
  ) {
    final duration =
        workout.endTime != null && workout.startTime != null
            ? workout.endTime!.difference(workout.startTime!)
            : Duration.zero;

    final activeDuration =
        workout.pausedDuration != null
            ? duration - workout.pausedDuration!
            : duration;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surface,
            getWorkoutColor(workout.type).withOpacity(0.05),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: getWorkoutColor(workout.type).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusLg),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (context) => TrackingHistoryDetailsScreen(workout: workout),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(spacingMd),
                      decoration: BoxDecoration(
                        color: getWorkoutColor(workout.type),
                        borderRadius: BorderRadius.circular(radiusMd),
                        boxShadow: [
                          BoxShadow(
                            color: getWorkoutColor(
                              workout.type,
                            ).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        getWorkoutIcon(workout.type),
                        color: Colors.white,
                        size: iconSizeMd,
                      ),
                    ),
                    const SizedBox(width: spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getWorkoutTypeName(workout.type),
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: getWorkoutColor(workout.type),
                            ),
                          ),
                          const SizedBox(height: spacingSm),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: iconSizeSm,
                                color: CustomAppColors.secondaryText,
                              ),
                              const SizedBox(width: spacingSm),
                              Text(
                                _formatDate(workout.startTime),
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color: CustomAppColors.secondaryText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete') {
                          final confirmed = await _showDeleteConfirmation(
                            context,
                          );
                          if (confirmed && workout.id != null) {
                            ref
                                .read(trackingHistoryProvider.notifier)
                                .deleteWorkout(workout.id!);
                          }
                        }
                      },
                      itemBuilder:
                          (context) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    deleteIcon,
                                    color: CustomAppColors.statusDanger,
                                    size: iconSizeSm,
                                  ),
                                  SizedBox(width: spacingSm),
                                  Text('Delete Workout'),
                                ],
                              ),
                            ),
                          ],
                      child: Container(
                        padding: const EdgeInsets.all(spacingSm),
                        decoration: BoxDecoration(
                          color: CustomAppColors.secondaryText.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Icon(
                          Icons.more_vert,
                          color: CustomAppColors.secondaryText,
                          size: iconSizeSm,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: spacingLg),

                // Metrics section
                Container(
                  padding: const EdgeInsets.all(spacingMd),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(radiusMd),
                    border: Border.all(
                      color: getWorkoutColor(workout.type).withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnhancedMetric(
                              icon: distanceIcon,
                              label: 'Distance',
                              value: _formatDistance(workout.totalDistance),
                              color: CustomAppColors.distance,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: CustomAppColors.secondaryText,
                            margin: const EdgeInsets.symmetric(
                              horizontal: spacingMd,
                            ),
                          ),
                          Expanded(
                            child: _buildEnhancedMetric(
                              icon: timeIcon,
                              label: 'Duration',
                              value: _formatDuration(activeDuration),
                              color: CustomAppColors.time,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: spacingMd),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnhancedMetric(
                              icon: speedIcon,
                              label: 'Avg Pace',
                              value: _formatPace(workout.averagePace),
                              color: CustomAppColors.colorA,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: CustomAppColors.secondaryText,
                            margin: const EdgeInsets.symmetric(
                              horizontal: spacingMd,
                            ),
                          ),
                          Expanded(
                            child:
                                workout.elevationGain != null &&
                                        workout.elevationGain! > 0
                                    ? _buildEnhancedMetric(
                                      icon: elevationIcon,
                                      label: 'Elevation',
                                      value:
                                          '${workout.elevationGain!.toInt()}m',
                                      color: CustomAppColors.statusSuccess,
                                    )
                                    : workout.calories != null
                                    ? _buildEnhancedMetric(
                                      icon: caloriesIcon,
                                      label: 'Calories',
                                      value: '${workout.calories}',
                                      color: CustomAppColors.statusWarning,
                                    )
                                    : _buildEnhancedMetric(
                                      icon: Icons.my_location,
                                      label: 'Points',
                                      value: '${workout.trackingPoints.length}',
                                      color: CustomAppColors.colorB,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Notes if available
                if (workout.notes != null && workout.notes!.isNotEmpty) ...[
                  const SizedBox(height: spacingMd),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(spacingMd),
                    decoration: BoxDecoration(
                      color: getWorkoutColor(workout.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(radiusMd),
                      border: Border.all(
                        color: getWorkoutColor(workout.type).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          noteIcon,
                          size: iconSizeSm,
                          color: getWorkoutColor(workout.type),
                        ),
                        const SizedBox(width: spacingSm),
                        Expanded(
                          child: Text(
                            workout.notes!,
                            style: TextStyle(
                              fontSize: 14,
                              color: CustomAppColors.secondaryText,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(spacingSm),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: spacingSm),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: CustomAppColors.secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _getWorkoutTypeName(WorkoutType type) {
    switch (type) {
      case WorkoutType.running:
        return 'Running';
      case WorkoutType.walking:
        return 'Walking';
      case WorkoutType.cycling:
        return 'Cycling';
      case WorkoutType.hiking:
        return 'Hiking';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today at ${_formatTime(date)}';
    } else if (dateOnly == yesterday) {
      return 'Yesterday at ${_formatTime(date)}';
    } else {
      return '${date.day}/${date.month}/${date.year} at ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters >= 1000) {
      return '${(distanceInMeters / 1000).toStringAsFixed(2)} km';
    } else {
      return '${distanceInMeters.toInt()} m';
    }
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

    return '${minutes}:${seconds.toString().padLeft(2, '0')} /km';
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Delete Workout'),
                content: const Text(
                  'Are you sure you want to delete this workout? This action cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: CustomAppColors.statusDanger,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
        ) ??
        false;
  }
}
