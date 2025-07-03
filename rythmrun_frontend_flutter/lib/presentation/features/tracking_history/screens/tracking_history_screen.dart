import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/models/tracking_history_state.dart';
import '../providers/tracking_history_provider.dart';

class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsState = ref.watch(trackingHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Tracking History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (workoutsState.workouts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
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
            Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              state.errorMessage!,
              style: TextStyle(color: Colors.red[600]),
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
          Icon(Icons.directions_run, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No Activities Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start tracking your workouts to see them here',
            style: TextStyle(fontSize: 16, color: Colors.grey),
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
          // TODO: Navigate to workout details screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tracking details coming soon!'),
              duration: Duration(seconds: 1),
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
                              color: Colors.grey[600],
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
                                Icon(Icons.delete, color: Colors.red, size: 20),
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
                    icon: Icons.straighten,
                    label: 'Distance',
                    value: _formatDistance(workout.totalDistance),
                  ),
                  _buildMetric(
                    icon: Icons.timer,
                    label: 'Duration',
                    value: _formatDuration(activeDuration),
                  ),
                  _buildMetric(
                    icon: Icons.speed,
                    label: 'Avg Pace',
                    value: _formatPace(workout.averagePace),
                  ),
                  if (workout.elevationGain != null &&
                      workout.elevationGain! > 0)
                    _buildMetric(
                      icon: Icons.trending_up,
                      label: 'Elevation',
                      value: '${workout.elevationGain!.toInt()}m',
                    )
                  else if (workout.calories != null)
                    _buildMetric(
                      icon: Icons.local_fire_department,
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
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.note, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          workout.notes!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
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
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  IconData _getWorkoutIcon(WorkoutType type) {
    switch (type) {
      case WorkoutType.running:
        return Icons.directions_run;
      case WorkoutType.walking:
        return Icons.directions_walk;
      case WorkoutType.cycling:
        return Icons.directions_bike;
      case WorkoutType.hiking:
        return Icons.terrain;
    }
  }

  Color _getWorkoutColor(WorkoutType type) {
    switch (type) {
      case WorkoutType.running:
        return Colors.orange;
      case WorkoutType.walking:
        return Colors.green;
      case WorkoutType.cycling:
        return Colors.blue;
      case WorkoutType.hiking:
        return Colors.brown;
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
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
        ) ??
        false;
  }
}
