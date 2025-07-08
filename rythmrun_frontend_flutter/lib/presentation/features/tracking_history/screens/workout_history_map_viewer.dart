import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/map_controller_button.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed_helper.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_segment_builder.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class WorkoutHistoryMapViewer extends StatefulWidget {
  final WorkoutSessionEntity workout;
  final bool showMapTiles;
  final bool showControls;

  const WorkoutHistoryMapViewer({
    super.key,
    required this.workout,
    this.showMapTiles = true,
    this.showControls = true,
  });

  @override
  State<WorkoutHistoryMapViewer> createState() =>
      _WorkoutHistoryMapViewerState();
}

class _WorkoutHistoryMapViewerState extends State<WorkoutHistoryMapViewer> {
  MapController? _mapController;
  final List<Marker> _markers = [];
  final List<Polyline> _solidPolylines = [];
  final List<Polyline> _dashedPolylines = [];
  bool _showMapTiles = true;

  // Default camera position
  LatLng _center = const LatLng(28.6139, 77.2090); // New Delhi coordinates
  double _zoom = 16.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _showMapTiles = widget.showMapTiles;
    _buildAndFitMap();
  }

  @override
  void didUpdateWidget(WorkoutHistoryMapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    debugPrint('🔄 didUpdateWidget called');
    debugPrint('  Old workout ID: ${oldWidget.workout.id}');
    debugPrint('  New workout ID: ${widget.workout.id}');
    debugPrint(
      '  Old tracking points: ${oldWidget.workout.trackingPoints.length}',
    );
    debugPrint(
      '  New tracking points: ${widget.workout.trackingPoints.length}',
    );

    // Rebuild the map visualization if the workout data changes
    if (widget.workout.id != oldWidget.workout.id ||
        widget.workout.trackingPoints.length !=
            oldWidget.workout.trackingPoints.length) {
      debugPrint('💡 Workout data changed, rebuilding visualization...');
      _buildAndFitMap();
    } else {
      debugPrint('📍 No significant changes detected');
    }
  }

  void _buildAndFitMap() {
    debugPrint('🏗️ _buildAndFitMap called');
    debugPrint(
      '  Tracking points available: ${widget.workout.trackingPoints.length}',
    );

    if (widget.workout.trackingPoints.isNotEmpty) {
      // Center map on workout start location
      final startPoint = widget.workout.trackingPoints.first;
      _center = LatLng(startPoint.latitude, startPoint.longitude);
      debugPrint(
        '  Setting center to: ${_center.latitude}, ${_center.longitude}',
      );

      _buildWorkoutVisualization();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('📐 Fitting map to workout bounds...');
          //Critical:  Add a small delay to ensure map has finished rendering
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _fitWorkoutToMap();
            }
          });
        }
      });
    } else {
      debugPrint('⚠️ No tracking points available for visualization');
    }
  }

  void _buildWorkoutVisualization() {
    debugPrint(
      '🔧 Building workout visualization for ${widget.workout.trackingPoints.length} points',
    );

    _markers.clear();
    _solidPolylines.clear();
    _dashedPolylines.clear();

    if (widget.workout.trackingPoints.isEmpty) return;

    // Build segments from workout data
    final segments = LiveMapSegmentBuilder.buildSegments(widget.workout);

    debugPrint('🎯 Built ${segments.length} segments for visualization');

    // Create polylines for each segment
    bool hasValidSegments = false;
    for (final segment in segments) {
      if (segment.points.length < 2) continue;

      final points =
          segment.points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();

      if (segment.status == WorkoutStatus.active) {
        _createSolidPolyline(points, widget.workout.type);
        hasValidSegments = true;
      } else if (segment.status == WorkoutStatus.paused) {
        _createDashedPolyline(points, widget.workout.type);
        hasValidSegments = true;
      }
    }

    // Fallback: if no valid segments, create a simple polyline from all points
    if (!hasValidSegments && widget.workout.trackingPoints.length >= 2) {
      debugPrint('⚠️ No valid segments found, creating fallback polyline');
      final allPoints =
          widget.workout.trackingPoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();
      _createSolidPolyline(allPoints, widget.workout.type);
    }

    // Add start and end markers
    _addStartMarker();
    _addEndMarker();

    setState(() {});
  }

  void _createSolidPolyline(List<LatLng> points, WorkoutType type) {
    debugPrint('✅ Creating solid polyline with ${points.length} points');
    final polyline = Polyline(
      points: points,
      color: getWorkoutColor(type),
      strokeWidth: 4,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    );
    _solidPolylines.add(polyline);
  }

  void _createDashedPolyline(List<LatLng> points, WorkoutType type) {
    debugPrint('✅ Creating dashed polyline with ${points.length} points');
    final polyline = Polyline(
      points: points,
      color: CustomAppColors.statusError,
      strokeWidth: 4,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      pattern: StrokePattern.dashed(segments: [10, 5]),
    );
    _dashedPolylines.add(polyline);
  }

  void _addStartMarker() {
    if (widget.workout.trackingPoints.isEmpty) return;

    final startPoint = widget.workout.trackingPoints.first;
    final startMarker = Marker(
      key: const ValueKey('start_marker'),
      point: LatLng(startPoint.latitude, startPoint.longitude),
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: CustomAppColors.statusSuccess,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
      ),
    );
    _markers.add(startMarker);
  }

  void _addEndMarker() {
    if (widget.workout.trackingPoints.isEmpty) return;

    final endPoint = widget.workout.trackingPoints.last;
    final endMarker = Marker(
      key: const ValueKey('end_marker'),
      point: LatLng(endPoint.latitude, endPoint.longitude),
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: CustomAppColors.statusError,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(stopIcon, color: Colors.white, size: 15),
      ),
    );
    _markers.add(endMarker);
  }

  void _fitWorkoutToMap() {
    if (widget.workout.trackingPoints.isEmpty || _mapController == null) return;

    try {
      // Calculate bounds for all tracking points
      double minLat = widget.workout.trackingPoints.first.latitude;
      double maxLat = widget.workout.trackingPoints.first.latitude;
      double minLng = widget.workout.trackingPoints.first.longitude;
      double maxLng = widget.workout.trackingPoints.first.longitude;

      for (final point in widget.workout.trackingPoints) {
        minLat = minLat < point.latitude ? minLat : point.latitude;
        maxLat = maxLat > point.latitude ? maxLat : point.latitude;
        minLng = minLng < point.longitude ? minLng : point.longitude;
        maxLng = maxLng > point.longitude ? maxLng : point.longitude;
      }

      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );

      _mapController!.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
    } catch (e) {
      debugPrint('⚠️ Error fitting map to workout: $e');
      // Fallback to centering on first point
      if (widget.workout.trackingPoints.isNotEmpty) {
        final startPoint = widget.workout.trackingPoints.first;
        _mapController!.move(
          LatLng(startPoint.latitude, startPoint.longitude),
          _zoom,
        );
      }
    }
  }

  void _toggleMapTiles() {
    setState(() {
      _showMapTiles = !_showMapTiles;
    });
  }

  void _centerOnStart() {
    if (widget.workout.trackingPoints.isNotEmpty && _mapController != null) {
      final startPoint = widget.workout.trackingPoints.first;
      _mapController!.move(
        LatLng(startPoint.latitude, startPoint.longitude),
        _zoom,
      );
    }
  }

  void _centerOnEnd() {
    if (widget.workout.trackingPoints.isNotEmpty && _mapController != null) {
      final endPoint = widget.workout.trackingPoints.last;
      _mapController!.move(
        LatLng(endPoint.latitude, endPoint.longitude),
        _zoom,
      );
    }
  }

  void _zoomIn() {
    final currentZoom = _mapController?.camera.zoom ?? _zoom;
    _mapController?.move(_mapController!.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController?.camera.zoom ?? _zoom;
    _mapController?.move(_mapController!.camera.center, currentZoom - 1);
  }

  @override
  Widget build(BuildContext context) {
    // Show loading state if map controller is not ready
    if (_mapController == null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusLg),
          color: Colors.red,
        ),
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }

    // Show empty state if no tracking points
    if (widget.workout.trackingPoints.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusLg),
          color: Colors.red,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radiusLg),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No route data available',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radiusLg),
        color:
            _showMapTiles
                ? Colors.transparent
                : (Colors.grey[100] ?? Colors.grey),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radiusLg),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController!,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _zoom,
                minZoom: 3,
                maxZoom: 19,
                backgroundColor:
                    _showMapTiles ? Colors.transparent : Colors.grey,
              ),
              children: [
                // Map tiles (optional)
                if (_showMapTiles)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                        'com.example.rythmrun_frontend_flutter',
                    maxZoom: 19,
                  ),

                // Polylines
                PolylineLayer(polylines: _solidPolylines),
                PolylineLayer(polylines: _dashedPolylines),

                // Markers
                MarkerLayer(markers: _markers),
              ],
            ),

            // Map controls
            if (widget.showControls)
              Positioned(
                bottom: spacingMd,
                right: spacingMd,
                child: Column(
                  children: [
                    buildMapControlButton(
                      icon: _showMapTiles ? Icons.layers_clear : Icons.layers,
                      onPressed: _toggleMapTiles,
                      tooltip: _showMapTiles ? 'Hide map' : 'Show map',
                    ),
                    const SizedBox(height: spacingSm),
                    buildMapControlButton(
                      icon: Icons.fit_screen,
                      onPressed: _fitWorkoutToMap,
                      tooltip: 'Fit workout',
                    ),
                    const SizedBox(height: spacingSm),
                    buildMapControlButton(
                      icon: Icons.play_arrow,
                      onPressed: _centerOnStart,
                      tooltip: 'Go to start',
                    ),
                    const SizedBox(height: spacingSm),
                    buildMapControlButton(
                      icon: Icons.stop,
                      onPressed: _centerOnEnd,
                      tooltip: 'Go to end',
                    ),
                    const SizedBox(height: spacingSm),
                    buildMapControlButton(
                      icon: Icons.zoom_in,
                      onPressed: _zoomIn,
                      tooltip: 'Zoom in',
                    ),
                    const SizedBox(height: spacingSm),
                    buildMapControlButton(
                      icon: Icons.zoom_out,
                      onPressed: _zoomOut,
                      tooltip: 'Zoom out',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
