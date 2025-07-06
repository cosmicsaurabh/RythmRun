import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_segment_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/map_controller_button.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed_helper.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_segment_builder.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/models/live_tracking_state.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/providers/live_tracking_provider.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class LiveMapFeed extends ConsumerStatefulWidget {
  const LiveMapFeed({super.key});

  @override
  ConsumerState<LiveMapFeed> createState() => _LiveMapFeedState();
}

class _LiveMapFeedState extends ConsumerState<LiveMapFeed> {
  MapController? _mapController;
  final List<Marker> _markers = [];
  final List<Polyline> _solidPolylines = [];
  final List<Polyline> _dashedPolylines = [];
  StreamSubscription<TrackingPointEntity>? _locationSubscription;

  // Default camera position (San Francisco)
  LatLng _center = const LatLng(37.4419, -122.1419);
  double _zoom = 16.0;

  // Track previous session state to detect changes
  WorkoutSessionEntity? _previousSession;

  @override
  void initState() {
    super.initState();
    print('🚀 LiveMapFeed initialized');
    _initializeMap();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    _mapController = MapController();

    // Get current location for initial camera position
    final currentLocation =
        await LiveTrackingService.instance.getCurrentLocation();
    if (currentLocation != null) {
      setState(() {
        _center = LatLng(currentLocation.latitude, currentLocation.longitude);
      });
    }

    // Listen to location updates
    _locationSubscription = LiveTrackingService.instance.locationStream.listen(
      (point) => _onLocationUpdate(point, ref.read(liveTrackingProvider)),
      onError: (error) {
        debugPrint('❌ Map location error: $error');
      },
    );
  }

  void _onLocationUpdate(
    TrackingPointEntity point,
    LiveTrackingState liveTrackingState,
  ) {
    if (_mapController == null) return;

    final newLatLng = LatLng(point.latitude, point.longitude);
    print('🌍 Location update received: ${point.latitude}, ${point.longitude}');

    // Validate location to prevent jumping (basic sanity check)
    if (!_isValidLocationForPolyline(
      newLatLng,
      liveTrackingState.currentSession,
    )) {
      print(
        '⚠️ Invalid location detected: ${point.latitude}, ${point.longitude}',
      );
      return;
    }

    // Update current location marker
    _updateCurrentLocationMarker(
      newLatLng,
      point,
      liveTrackingState.currentSession,
    );

    // Update tracking path
    _updateTrackingPath();

    // Animate camera to follow current location
    _animateToCurrentLocation(newLatLng);
  }

  bool _isValidLocationForPolyline(
    LatLng location,
    WorkoutSessionEntity? session,
  ) {
    // Different thresholds based on session status
    double threshold;
    if (session?.status == WorkoutStatus.active) {
      threshold = 300; // Stricter for active
    } else if (session?.status == WorkoutStatus.paused) {
      threshold = 1000; // More lenient for paused
    } else {
      return true; // Allow all for other statuses
    }
    // Basic validation - check if coordinates are within valid ranges
    if (location.latitude < -90 || location.latitude > 90) return false;
    if (location.longitude < -180 || location.longitude > 180) return false;

    // Check for obviously invalid coordinates (0,0 or similar)
    if (location.latitude == 0 && location.longitude == 0) return false;

    if (session?.trackingPoints.isNotEmpty ?? false) {
      final lastPoint = session!.trackingPoints.last;
      final distance = calculateDistance(
        LatLng(lastPoint.latitude, lastPoint.longitude),
        location,
      );
      if (distance > threshold) {
        print(
          '⚠️ Large location jump detected: ${distance.toStringAsFixed(2)}m',
        );
        return false;
      }
    }
    return true;
  }

  void _updateTrackingPath() {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    // If no session exists or session has ended, clear the map
    if (session == null || session.status == WorkoutStatus.completed) {
      print('🧹 No session or completed, clearing map data');
      _clearMapData();
      return;
    }

    if (session.status == WorkoutStatus.notStarted) {
      print('🧹 Session not started, clearing map data');
      _clearMapData();
      return;
    }

    // If no tracking points, just clear polylines but keep current location marker
    if (session.trackingPoints.isEmpty) {
      print('📍 No tracking points, clearing tracking data');
      _clearTrackingData();
      return;
    }

    print(
      '📊 Processing ${session.trackingPoints.length} tracking points and ${session.statusChanges.length} status changes',
    );

    // Build segments based on workout status changes
    final List<TrackingSegment> segments = LiveMapSegmentBuilder.buildSegments(
      session,
    );

    // Debug segments
    LiveMapSegmentBuilder.debugSegments(segments);

    // Clear existing polylines
    _solidPolylines.clear();
    _dashedPolylines.clear();

    // Create polylines for each segment
    for (final segment in segments) {
      if (segment.points.length < 2) {
        continue;
      }

      final List<LatLng> points =
          segment.points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();

      if (segment.status == WorkoutStatus.active) {
        _createSolidPolylineFromPoints(points, session.type);
      } else if (segment.status == WorkoutStatus.paused) {
        _createDashedPolylineFromPoints(points, session.type);
      }
    }

    // Add start marker if we have any points
    if (session.trackingPoints.isNotEmpty) {
      _addStartMarker(session.trackingPoints.first);
    }
  }

  void _createSolidPolylineFromPoints(List<LatLng> points, WorkoutType type) {
    final solidPolyline = Polyline(
      points: points,
      color: getWorkoutColor(type),
      strokeWidth: 6,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    );

    setState(() {
      _solidPolylines.add(solidPolyline);
    });
    print('✅ Created solid polyline with ${points.length} points');
  }

  void _createDashedPolylineFromPoints(List<LatLng> points, WorkoutType type) {
    final dashedPolyline = Polyline(
      points: points,
      color: CustomAppColors.statusError,
      strokeWidth: 3,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      pattern: StrokePattern.dashed(segments: [10, 5]),
    );

    setState(() {
      _dashedPolylines.add(dashedPolyline);
    });
    print('✅ Created dashed polyline with ${points.length} points');
  }

  void _updateCurrentLocationMarker(
    LatLng position,
    TrackingPointEntity point,
    WorkoutSessionEntity? session,
  ) {
    // Remove old current location marker
    _markers.removeWhere(
      (marker) => marker.key == const ValueKey('current_location'),
    );

    // Get dynamic color based on workout type and speed
    final markerColor = getCurrentLocationMarkerColor(point, session);
    final markerIcon = getCurrentLocationIcon(session);

    // Add new current location marker
    final marker = Marker(
      key: const ValueKey('current_location'),
      point: position,
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: markerColor,
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
        child: Icon(
          markerIcon,
          color: Colors.white,
          size: 20, // Icon fits properly now
        ),
      ),
    );

    setState(() {
      _markers.add(marker);
    });
  }

  void _clearMapData() {
    setState(() {
      _markers.clear();
      _dashedPolylines.clear();
      _solidPolylines.clear();
    });
  }

  void _clearTrackingData() {
    setState(() {
      // Remove all markers except current location
      _markers.removeWhere(
        (marker) => marker.key != const ValueKey('current_location'),
      );
      // Clear all polylines
      _dashedPolylines.clear();
      _solidPolylines.clear();
    });
  }

  void _addStartMarker(TrackingPointEntity startPoint) {
    // Remove old start marker
    _markers.removeWhere(
      (marker) => marker.key == const ValueKey('start_location'),
    );

    final startMarker = Marker(
      key: const ValueKey('start_location'),
      point: LatLng(startPoint.latitude, startPoint.longitude),
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: CustomAppColors.statusSuccess,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
      ),
    );

    setState(() {
      _markers.add(startMarker);
    });
  }

  void _animateToCurrentLocation(LatLng position) {
    _mapController?.move(position, _zoom);
  }

  void _handleSessionStateChanges(WorkoutSessionEntity? currentSession) {
    // Only process if the session actually changed
    if (_previousSession != currentSession) {
      if (_previousSession != null &&
          currentSession != null &&
          _previousSession!.status != currentSession.status) {
        print(
          '🧹 Session state changed: ${_previousSession!.status} -> ${currentSession.status}',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateTrackingPath();
        });
      }
      // If sess}ion ended (was active, now null or completed)
      if (_previousSession != null &&
          (currentSession == null ||
              currentSession.status == WorkoutStatus.completed)) {
        debugPrint('🧹 Session ended, clearing map data');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _clearMapData();
        });
      }

      // Update previous session reference
      _previousSession = currentSession;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final liveTrackingState = ref.watch(liveTrackingProvider);

        // Check for session state changes
        _handleSessionStateChanges(liveTrackingState.currentSession);

        return Container(
          height: double.infinity, // Adjust height as needed
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radiusLg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            // borderRadius: BorderRadius.circular(radiusLg),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: _zoom,
                    minZoom: 3,
                    maxZoom: 19,
                    onTap: (tapPosition, point) {
                      // Handle map tap if needed
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.rythmrun_frontend_flutter',
                      maxZoom: 19,
                    ),
                    PolylineLayer(polylines: _solidPolylines),
                    PolylineLayer(polylines: _dashedPolylines),
                    MarkerLayer(markers: _markers),
                  ],
                ),

                // Map controls overlay
                Positioned(
                  bottom: spacingMd,
                  right: spacingMd,
                  child: Column(
                    children: [
                      buildMapControlButton(
                        icon: Icons.my_location,
                        onPressed: _centerOnCurrentLocation,
                        tooltip: 'Center on current location',
                      ),
                      const SizedBox(height: spacingSm),
                      buildMapControlButton(
                        icon: Icons.fit_screen,
                        onPressed: _fitTrackingPath,
                        tooltip: 'Fit tracking path',
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

                // Status overlay
                if (liveTrackingState.isLoading)
                  const Positioned(
                    top: spacingMd,
                    left: spacingMd,
                    right: spacingMd,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(spacingSm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: spacingSm),
                            Text('Loading location...'),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Error overlay
                if (liveTrackingState.errorMessage != null)
                  Positioned(
                    bottom: spacingMd,
                    left: spacingMd,
                    right: spacingXl * 3,
                    child: Card(
                      color: CustomAppColors.statusError,
                      child: Padding(
                        padding: const EdgeInsets.all(spacingSm),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: CustomAppColors.white),
                            const SizedBox(width: spacingSm),
                            Expanded(
                              child: Text(
                                liveTrackingState.errorMessage!,
                                style: TextStyle(color: CustomAppColors.white),
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
      },
    );
  }

  void _centerOnCurrentLocation() async {
    final currentLocation =
        await LiveTrackingService.instance.getCurrentLocation();
    if (currentLocation != null && _mapController != null) {
      // final currentZoom = _mapController!.camera.zoom;

      // // Fixed offset values to reliably show current location in lower half
      // double latOffset;
      // if (currentZoom >= 18) {
      //   latOffset = 0.002; // Very close zoom - small offset
      // } else if (currentZoom >= 15) {
      //   latOffset = 0.005; // Close zoom - medium offset
      // } else if (currentZoom >= 12) {
      //   latOffset = 0.010; // Medium zoom - larger offset
      // } else if (currentZoom >= 10) {
      //   latOffset = 0.020; // Far zoom - large offset
      // } else {
      //   latOffset = 0.040; // Very far zoom - very large offset
      // }

      // _mapController!.move(
      //   LatLng(
      //     currentLocation.latitude + latOffset, // Move center up (north)
      //     currentLocation.longitude,
      //   ),
      //   currentZoom,
      // );
      _mapController!.move(
        LatLng(currentLocation.latitude, currentLocation.longitude),
        _zoom,
      );
    }
  }

  void _fitTrackingPath() {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    if (session == null ||
        session.trackingPoints.isEmpty ||
        _mapController == null)
      return;

    // Calculate bounds for all tracking points
    double minLat = session.trackingPoints.first.latitude;
    double maxLat = session.trackingPoints.first.latitude;
    double minLng = session.trackingPoints.first.longitude;
    double maxLng = session.trackingPoints.first.longitude;

    for (final point in session.trackingPoints) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));

    _mapController!.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  void _zoomIn() {
    final currentZoom = _mapController?.camera.zoom ?? _zoom;
    _mapController?.move(_mapController!.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController?.camera.zoom ?? _zoom;
    _mapController?.move(_mapController!.camera.center, currentZoom - 1);
  }

  void _manualClearMap() {
    print('🧹 Manual clear map triggered');
    _clearMapData();
  }
}
