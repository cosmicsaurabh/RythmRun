import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
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
  final List<Polyline> _polylines = [];
  StreamSubscription<TrackingPointEntity>? _locationSubscription;

  // Default camera position (San Francisco)
  LatLng _center = const LatLng(37.4419, -122.1419);
  double _zoom = 16.0;

  // Track previous session state to detect changes
  WorkoutSessionEntity? _previousSession;

  @override
  void initState() {
    super.initState();
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
      _onLocationUpdate,
      onError: (error) {
        debugPrint('❌ Map location error: $error');
      },
    );
  }

  void _onLocationUpdate(TrackingPointEntity point) {
    if (_mapController == null) return;

    final newLatLng = LatLng(point.latitude, point.longitude);

    // Validate location to prevent jumping (basic sanity check)
    if (!_isValidLocation(newLatLng)) {
      debugPrint(
        '⚠️ Invalid location detected: ${point.latitude}, ${point.longitude}',
      );
      return;
    }

    // Update current location marker
    _updateCurrentLocationMarker(newLatLng, point);

    // Update tracking path
    _updateTrackingPath();

    // Animate camera to follow current location
    _animateToCurrentLocation(newLatLng);
  }

  bool _isValidLocation(LatLng location) {
    // Basic validation - check if coordinates are within valid ranges
    if (location.latitude < -90 || location.latitude > 90) return false;
    if (location.longitude < -180 || location.longitude > 180) return false;

    // Check for obviously invalid coordinates (0,0 or similar)
    if (location.latitude == 0 && location.longitude == 0) return false;

    // Check for unrealistic jumps (more than 1km in one update)
    if (_markers.isNotEmpty) {
      final currentLocationMarker = _markers.firstWhere(
        (marker) => marker.key == const ValueKey('current_location'),
        orElse: () => _markers.first,
      );

      if (currentLocationMarker.point != null) {
        final distance = _calculateDistance(
          currentLocationMarker.point!,
          location,
        );

        // If distance is more than 1000 meters, it's likely a jump
        if (distance > 1000) {
          debugPrint(
            '⚠️ Large location jump detected: ${distance.toStringAsFixed(2)}m',
          );
          return false;
        }
      }
    }

    return true;
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    double lat1Rad = point1.latitude * (pi / 180);
    double lat2Rad = point2.latitude * (pi / 180);
    double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    double deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);

    double a =
        sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) *
            cos(lat2Rad) *
            sin(deltaLngRad / 2) *
            sin(deltaLngRad / 2);
    double c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }

  bool _isValidLocationForPolyline(LatLng location) {
    // Basic validation - check if coordinates are within valid ranges
    if (location.latitude < -90 || location.latitude > 90) return false;
    if (location.longitude < -180 || location.longitude > 180) return false;

    // Check for obviously invalid coordinates (0,0 or similar)
    if (location.latitude == 0 && location.longitude == 0) return false;

    return true;
  }

  void _updateCurrentLocationMarker(
    LatLng position,
    TrackingPointEntity point,
  ) {
    // Remove old current location marker
    _markers.removeWhere(
      (marker) => marker.key == const ValueKey('current_location'),
    );

    // Get dynamic color based on workout type and speed
    final markerColor = _getCurrentLocationMarkerColor(point);
    final markerIcon = _getCurrentLocationIcon();

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

  // Get marker color based on workout type and speed
  Color _getCurrentLocationMarkerColor(TrackingPointEntity point) {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    // If there's an active workout, use workout color
    if (session != null) {
      return _getWorkoutColor(session.type);
    }

    // Otherwise, use speed-based color
    final speed = point.speed ?? 0.0; // m/s
    if (speed < 0.5) return Colors.grey; // Stationary
    if (speed < 1.5) return Colors.blue; // Walking
    if (speed < 3.0) return Colors.orange; // Jogging
    return Colors.red; // Running
  }

  // Get marker icon based on workout type
  IconData _getCurrentLocationIcon() {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    if (session != null) {
      switch (session.type) {
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

    return Icons.my_location; // Default
  }

  void _updateTrackingPath() {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    // If no session exists or session has ended, clear the map
    if (session == null || session.status == WorkoutStatus.completed) {
      _clearMapData();
      return;
    }

    // If no tracking points, just clear polylines but keep current location marker
    if (session.trackingPoints.isEmpty) {
      _clearTrackingData();
      return;
    }

    // Create polyline from tracking points - filter out invalid locations
    final allPoints =
        session.trackingPoints
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

    // Filter out invalid points and large jumps
    final List<LatLng> validPoints = [];
    for (int i = 0; i < allPoints.length; i++) {
      final point = allPoints[i];

      // Basic validation
      if (!_isValidLocationForPolyline(point)) {
        debugPrint(
          '🚫 Filtered invalid polyline point: ${point.latitude}, ${point.longitude}',
        );
        continue;
      }

      // Check for distance jumps (except for the first point)
      if (validPoints.isNotEmpty) {
        final distance = _calculateDistance(validPoints.last, point);
        if (distance > 1000) {
          debugPrint(
            '🚫 Filtered polyline jump: ${distance.toStringAsFixed(2)}m from ${validPoints.last} to $point',
          );
          continue;
        }
      }

      validPoints.add(point);
    }

    final points = validPoints;

    // Remove old polyline
    _polylines.removeWhere((polyline) => polyline.strokeWidth == 4);

    // Add new polyline only if we have enough valid points
    if (points.length >= 2) {
      final polyline = Polyline(
        points: points,
        color: _getWorkoutColor(session.type),
        strokeWidth: 4,
        pattern:
            session.status == WorkoutStatus.paused
                ? StrokePattern.dashed(segments: [10, 5])
                : StrokePattern.solid(),
      );

      setState(() {
        _polylines.add(polyline);
      });
    } else {
      debugPrint(
        '⚠️ Not enough valid points to create polyline: ${points.length}',
      );
    }

    // Add start marker if we have valid points
    if (points.isNotEmpty) {
      // Use the first valid point for the start marker
      final firstValidPoint = points.first;
      final startPointEntity = session.trackingPoints.firstWhere(
        (trackingPoint) =>
            LatLng(trackingPoint.latitude, trackingPoint.longitude) ==
            firstValidPoint,
        orElse: () => session.trackingPoints.first,
      );
      _addStartMarker(startPointEntity);
    }
  }

  void _clearMapData() {
    setState(() {
      _markers.clear();
      _polylines.clear();
    });
  }

  void _clearTrackingData() {
    setState(() {
      // Remove all markers except current location
      _markers.removeWhere(
        (marker) => marker.key != const ValueKey('current_location'),
      );
      // Clear all polylines
      _polylines.clear();
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

  void _handleSessionStateChanges(WorkoutSessionEntity? currentSession) {
    // If session ended (was active, now null or completed)
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
                    PolylineLayer(polylines: _polylines),
                    MarkerLayer(markers: _markers),
                  ],
                ),

                // Map controls overlay
                Positioned(
                  bottom: spacingMd,
                  right: spacingMd,
                  child: Column(
                    children: [
                      _buildMapControlButton(
                        icon: Icons.my_location,
                        onPressed: _centerOnCurrentLocation,
                        tooltip: 'Center on current location',
                      ),
                      const SizedBox(height: spacingSm),
                      _buildMapControlButton(
                        icon: Icons.fit_screen,
                        onPressed: _fitTrackingPath,
                        tooltip: 'Fit tracking path',
                      ),
                      const SizedBox(height: spacingSm),
                      _buildMapControlButton(
                        icon: Icons.zoom_in,
                        onPressed: _zoomIn,
                        tooltip: 'Zoom in',
                      ),
                      const SizedBox(height: spacingSm),
                      _buildMapControlButton(
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

  Widget _buildMapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: CustomAppColors.black,
        borderRadius: BorderRadius.circular(radiusSm),
        boxShadow: [
          // First shadow layer (e.g. black-100 token)
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, 4),
            blurRadius: 4, // same token for blur
            spreadRadius: -1,
          ),

          BoxShadow(
            color: Colors.black.withOpacity(
              0.2,
            ), // adjust for --sds-color-black-200
            offset: const Offset(0, 4),
            blurRadius: 4,
            spreadRadius: -1,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 24, color: CustomAppColors.white),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: const EdgeInsets.all(spacingMd),
      ),
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
}
