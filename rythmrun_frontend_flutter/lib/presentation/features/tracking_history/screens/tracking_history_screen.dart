import 'package:flutter/cupertino.dart';
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
    final notifier = ref.read(trackingHistoryProvider.notifier);

    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
          ),
          padding: const EdgeInsets.fromLTRB(
            spacingMd,
            spacingXl,
            spacingMd,
            spacingMd,
          ),
          child: SafeArea(
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
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(height: spacingSm),
                        // AppBar Card: Overall Statistics
                        Text(
                          notifier.getOverallStatsText(),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: CustomAppColors.secondaryText),
                        ),
                      ],
                    ),
                    // Filter toggle button
                    IconButton(
                      onPressed: () => _showFilterBottomSheet(context, ref),
                      icon: Icon(
                        state.hasFilters
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                        color:
                            state.hasFilters
                                ? CustomAppColors.progressSky
                                : CustomAppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ],
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

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    if (state.isLoading) {
      return _buildLoadingState();
    }

    if (state.errorMessage != null) {
      return _buildErrorState(context, ref, state.errorMessage);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: spacingMd),

          // Filter Card: Filtered Statistics (only show if filters applied)
          if (state.hasFilters) ...[
            _buildFilteredStatsCard(context, ref, state),
            const SizedBox(height: spacingLg),
          ],

          // Active filters display
          if (state.hasFilters) ...[
            _buildActiveFilters(context, ref, state),
            const SizedBox(height: spacingMd),
          ],

          // Workouts list
          if (state.workouts.isEmpty)
            _buildEmptyState(context, state.hasFilters)
          else
            _buildWorkoutsList(context, ref, state.workouts),
        ],
      ),
    );
  }

  // Filter Card: Shows statistics for current filter
  Widget _buildFilteredStatsCard(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    final notifier = ref.read(trackingHistoryProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(
          color: CustomAppColors.progressSky.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filtered Results',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              TextButton(
                onPressed: () => notifier.clearFilters(),
                child: Text(
                  'Clear Filters',
                  style: TextStyle(color: CustomAppColors.progressSky),
                ),
              ),
            ],
          ),
          const SizedBox(height: spacingSm),
          Text(
            notifier.getFilteredStatsText(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: CustomAppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  // Active filters display
  Widget _buildActiveFilters(
    BuildContext context,
    WidgetRef ref,
    TrackingHistoryState state,
  ) {
    final notifier = ref.read(trackingHistoryProvider.notifier);
    final List<Widget> filterChips = [];

    if (state.selectedWorkoutType != null) {
      filterChips.add(
        FilterChip(
          label: Text(state.selectedWorkoutType!.toUpperCase()),
          onDeleted: () => notifier.setWorkoutTypeFilter(null),
          onSelected: (_) => notifier.setWorkoutTypeFilter(null),
          selectedColor: getWorkoutColor(
            getReverseWorkoutTypeName(state.selectedWorkoutType!),
          ).withOpacity(0.2),
          selected: true,
        ),
      );
    }

    if (state.startDate != null || state.endDate != null) {
      final dateText =
          state.startDate != null && state.endDate != null
              ? '${_formatShortDate(state.startDate!)} - ${_formatShortDate(state.endDate!)}'
              : state.startDate != null
              ? 'From ${_formatShortDate(state.startDate!)}'
              : 'Until ${_formatShortDate(state.endDate!)}';

      filterChips.add(
        FilterChip(
          label: Text(dateText),
          onDeleted: () => notifier.setDateRangeFilter(),
          onSelected: (_) => notifier.setDateRangeFilter(),
          selectedColor: CustomAppColors.colorB.withOpacity(0.2),
          selected: true,
        ),
      );
    }

    return Wrap(spacing: spacingSm, children: filterChips);
  }

  Widget _buildWorkoutsList(
    BuildContext context,
    WidgetRef ref,
    List<WorkoutSessionEntity> workouts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activities (${workouts.length})',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: spacingMd),
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

  Widget _buildEmptyState(BuildContext context, bool hasFilters) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilters ? Icons.search_off : Icons.fitness_center,
              size: 64.0,
              color: CustomAppColors.secondaryText,
            ),
            const SizedBox(height: spacingLg),
            Text(
              hasFilters ? 'No Activities Found' : 'No Activities Yet',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: CustomAppColors.secondaryText,
              ),
            ),
            const SizedBox(height: spacingSm),
            Text(
              hasFilters
                  ? 'Try adjusting your filters to see more activities.'
                  : 'Start your fitness journey today!\nTrack your runs, walks, bike rides, and hikes.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: CustomAppColors.secondaryText,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (!hasFilters) ...[
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
                child: Text(
                  'Ready to get started?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(spacingXl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(color: CustomAppColors.secondaryText),
              const SizedBox(height: spacingMd),
              Text(
                'Loading workouts...',
                style: TextStyle(color: CustomAppColors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64.0,
              color: CustomAppColors.statusDanger,
            ),
            const SizedBox(height: spacingLg),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: CustomAppColors.statusDanger,
              ),
            ),
            const SizedBox(height: spacingSm),
            Text(
              error ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CustomAppColors.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: spacingLg),
            ElevatedButton(
              onPressed:
                  () => ref.read(trackingHistoryProvider.notifier).refresh(),
              child: Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // Filter Bottom Sheet
  void _showFilterBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Consumer(
            builder: (context, ref, child) {
              final notifier = ref.read(trackingHistoryProvider.notifier);
              final state = ref.watch(trackingHistoryProvider);

              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radiusXl),
                  ),
                ),
                padding: EdgeInsets.only(
                  left: spacingLg,
                  right: spacingLg,
                  top: spacingLg,
                  bottom: MediaQuery.of(context).viewInsets.bottom + spacingLg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filter Activities',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: spacingLg),

                    // Workout Type Filter
                    Text(
                      'Workout Type',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: spacingSm),
                    Wrap(
                      spacing: spacingSm,
                      children: [
                        FilterChip(
                          label: Text('All'),
                          selected: state.selectedWorkoutType == null,
                          onSelected:
                              (_) => notifier.setWorkoutTypeFilter(null),
                        ),
                        ...notifier.getWorkoutTypeOptions().map(
                          (type) => FilterChip(
                            label: Text(type.toUpperCase()),
                            selected: state.selectedWorkoutType == type,
                            onSelected:
                                (_) => notifier.setWorkoutTypeFilter(
                                  state.selectedWorkoutType == type
                                      ? null
                                      : type,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: spacingLg),

                    // Date Range
                    Text(
                      'Date Range',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: spacingSm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _selectDateRange(context, ref),
                            icon: Icon(Icons.date_range),
                            label: Text(
                              state.startDate != null && state.endDate != null
                                  ? '${_formatShortDate(state.startDate!)} - ${_formatShortDate(state.endDate!)}'
                                  : 'Select Date Range',
                            ),
                          ),
                        ),
                        if (state.startDate != null ||
                            state.endDate != null) ...[
                          const SizedBox(width: spacingSm),
                          IconButton(
                            onPressed: () => notifier.setDateRangeFilter(),
                            icon: Icon(Icons.clear),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: spacingLg),

                    // Clear All Filters
                    if (state.hasFilters)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            notifier.clearFilters();
                            Navigator.pop(context);
                          },
                          child: Text('Clear All Filters'),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Future<void> _selectDateRange(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(trackingHistoryProvider.notifier);
    final state = ref.read(trackingHistoryProvider);

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange:
          state.startDate != null && state.endDate != null
              ? DateTimeRange(start: state.startDate!, end: state.endDate!)
              : null,
    );

    if (picked != null) {
      notifier.setDateRangeFilter(startDate: picked.start, endDate: picked.end);
    }
  }

  String _formatShortDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
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
                            getWorkoutTypeName(workout.type),
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
                    // Delete button
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete') {
                          final shouldDelete = await _showDeleteConfirmation(
                            context,
                          );
                          if (shouldDelete) {
                            ref
                                .read(trackingHistoryProvider.notifier)
                                .deleteWorkout(workout.id!);
                          }
                        }
                      },
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    color: CustomAppColors.statusDanger,
                                  ),
                                  const SizedBox(width: spacingSm),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
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
                            child: _buildEnhancedMetric(
                              icon: caloriesIcon,
                              label: 'Calories',
                              value: workout.calories?.toString() ?? '--',
                              color: CustomAppColors.colorB,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
