import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed_helper.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/screens/workout_history_map_viewer.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class TrackingHistoryDetailsScreen extends StatefulWidget {
  final WorkoutSessionEntity workout;

  const TrackingHistoryDetailsScreen({super.key, required this.workout});

  @override
  State<TrackingHistoryDetailsScreen> createState() =>
      _TrackingHistoryDetailsScreenState();
}

class _TrackingHistoryDetailsScreenState
    extends State<TrackingHistoryDetailsScreen> {
  bool _showMapTiles = true;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Details'),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map view
                Container(
                  height: 400,
                  child: WorkoutHistoryMapViewer(
                    workout: widget.workout,
                    showMapTiles: _showMapTiles,
                    showControls: true,
                  ),
                ),

                const SizedBox(height: 20),
                _buildComprehensiveStats(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComprehensiveStats() {
    final duration =
        widget.workout.endTime != null && widget.workout.startTime != null
            ? widget.workout.endTime!.difference(widget.workout.startTime!)
            : Duration.zero;

    final activeDuration = widget.workout.activeDuration ?? duration;
    final pausedDuration = widget.workout.pausedDuration ?? Duration.zero;
    final totalDuration = activeDuration + pausedDuration;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  getCurrentLocationIcon(widget.workout),
                  color: getWorkoutColor(widget.workout.type),
                  size: iconSizeLg,
                ),
                const SizedBox(width: spacingMd),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getWorkoutTypeString(widget.workout.type),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatFullDate(widget.workout.startTime),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: spacingLg),

            // Main stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Distance',
                  '${(widget.workout.totalDistance / 1000).toStringAsFixed(2)} km',
                  Icons.route,
                ),

                _buildStatColumn(
                  'Avg Pace',
                  _formatPace(widget.workout.averagePace),
                  Icons.trending_up,
                ),
              ],
            ),

            const SizedBox(height: spacingLg),

            // Secondary stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Total Time',
                  _formatDuration(totalDuration),
                  Icons.play_arrow,
                ),
                _buildStatColumn(
                  'Active Time',
                  _formatDuration(activeDuration),
                  Icons.play_arrow,
                ),
              ],
            ),

            const SizedBox(height: spacingLg),

            // Time details row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Start Time',
                  _formatTime(widget.workout.startTime),
                  Icons.play_circle_outline,
                ),
                _buildStatColumn(
                  'End Time',
                  _formatTime(widget.workout.endTime),
                  Icons.stop_circle_outlined,
                ),
              ],
            ),

            // Additional stats if available
            if (widget.workout.elevationGain != null &&
                    widget.workout.elevationGain! > 0 ||
                widget.workout.calories != null) ...[
              const SizedBox(height: spacingLg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (widget.workout.elevationGain != null &&
                      widget.workout.elevationGain! > 0) ...[
                    _buildStatColumn(
                      'Elevation',
                      '${widget.workout.elevationGain!.toInt()}m',
                      Icons.terrain,
                    ),
                  ],
                  if (widget.workout.calories != null) ...[
                    _buildStatColumn(
                      'Calories',
                      '${widget.workout.calories}',
                      Icons.local_fire_department,
                    ),
                  ],
                ],
              ),
            ],

            // Notes if available
            if (widget.workout.notes != null &&
                widget.workout.notes!.isNotEmpty) ...[
              const SizedBox(height: spacingLg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(spacingMd),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.note, size: 16, color: Colors.grey),
                        const SizedBox(width: spacingSm),
                        Text(
                          'Notes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: spacingSm),
                    Text(
                      widget.workout.notes!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
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
      return 'Today at ${_formatTime(date)}';
    } else if (dateOnly == yesterday) {
      return 'Yesterday at ${_formatTime(date)}';
    } else {
      return '${date.day}/${date.month}/${date.year} at ${_formatTime(date)}';
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

  int _getSegmentCount() {
    // This would use the segment builder to count segments
    // For now, return a placeholder
    return widget.workout.statusChanges?.length ?? 1;
  }

  String _getWorkoutTypeString(WorkoutType type) {
    return type.name[0].toUpperCase() + type.name.substring(1);
  }
}
