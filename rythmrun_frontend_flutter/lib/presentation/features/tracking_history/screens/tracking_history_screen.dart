import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
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
      appBar: AppBar(
        title: const Text(
          'Tracking History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (workoutsState.workouts.isNotEmpty)
            IconButton(
              icon: const Icon(refreshIcon),
              onPressed: () {
                ref.read(trackingHistoryProvider.notifier).refresh();
              },
            ),
        ],
      ),
      body: _buildBody(context, ref, workoutsState),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              errorOutlineIcon,
              size: 60,
              color: CustomAppColors.statusDanger,
            ),
            const SizedBox(height: 16),
            Text(
              state.errorMessage!,
              style: TextStyle(color: CustomAppColors.statusDanger),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(trackingHistoryProvider.notifier).refresh();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.workouts.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(trackingHistoryProvider.notifier).refresh();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.workouts.length,
        itemBuilder: (context, index) {
          final workout = state.workouts[index];
          return _buildWorkoutCard(context, ref, workout);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(runningIcon, size: 80, color: CustomAppColors.secondaryText),
          SizedBox(height: 16),
          Text(
            'No Activities Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: CustomAppColors.secondaryText,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start tracking your workouts to see them here',
            style: TextStyle(
              fontSize: 16,
              color: CustomAppColors.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) => TrackingHistoryDetailsScreen(workout: workout),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with workout type and date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getWorkoutIcon(workout.type),
                        color: _getWorkoutColor(workout.type),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getWorkoutTypeName(workout.type),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatDate(workout.startTime),
                            style: TextStyle(
                              fontSize: 14,
                              color: CustomAppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text('Delete'),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Workout metrics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric(
                    icon: distanceIcon,
                    label: 'Distance',
                    value: _formatDistance(workout.totalDistance),
                  ),
                  _buildMetric(
                    icon: timeIcon,
                    label: 'Duration',
                    value: _formatDuration(activeDuration),
                  ),
                  _buildMetric(
                    icon: speedIcon,
                    label: 'Avg Pace',
                    value: _formatPace(workout.averagePace),
                  ),
                  if (workout.elevationGain != null &&
                      workout.elevationGain! > 0)
                    _buildMetric(
                      icon: elevationIcon,
                      label: 'Elevation',
                      value: '${workout.elevationGain!.toInt()}m',
                    )
                  else if (workout.calories != null)
                    _buildMetric(
                      icon: caloriesIcon,
                      label: 'Calories',
                      value: '${workout.calories}',
                    ),
                ],
              ),
              // Notes if available
              if (workout.notes != null && workout.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CustomAppColors.surfaceBackgroundLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        noteIcon,
                        size: 16,
                        color: CustomAppColors.secondaryText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          workout.notes!,
                          style: TextStyle(
                            fontSize: 14,
                            color: CustomAppColors.secondaryText,
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
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: CustomAppColors.secondaryText),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: CustomAppColors.secondaryText),
        ),
      ],
    );
  }

  IconData _getWorkoutIcon(WorkoutType type) {
    switch (type) {
      case WorkoutType.running:
        return runningIcon;
      case WorkoutType.walking:
        return walkingIcon;
      case WorkoutType.cycling:
        return cyclingIcon;
      case WorkoutType.hiking:
        return hikingIcon;
    }
  }

  Color _getWorkoutColor(WorkoutType type) {
    switch (type) {
      case WorkoutType.running:
        return CustomAppColors.running;
      case WorkoutType.walking:
        return CustomAppColors.walking;
      case WorkoutType.cycling:
        return CustomAppColors.cycling;
      case WorkoutType.hiking:
        return CustomAppColors.hiking;
    }
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
