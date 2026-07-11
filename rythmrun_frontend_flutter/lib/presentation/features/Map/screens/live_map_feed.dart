import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/live_tracking_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/location_error_handler.dart';
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

class _LiveMapFeedState extends ConsumerState<LiveMapFeed>
    with TickerProviderStateMixin {
  MapController? _mapController;
  late final AnimationController _animationController;
  final List<Marker> _markers = [];
  final List<Polyline> _solidPolylines = [];
  final List<Polyline> _dashedPolylines = [];

  // Default camera position (San Francisco)
  LatLng _center = const LatLng(28.6139, 77.2090); // Default to Delhi
  final double _zoom = 16.0;

  // Track previous session state to detect changes
  WorkoutSessionEntity? _previousSession;

  // Follow/interaction flags
  bool _isFollowing = false; // when true, camera follows current location
  bool _manualByUser = false; // set true on any user interaction

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _initializeMap();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CustomAppColors.statusError,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(spacingMd),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    _mapController = MapController();

    // Get current location for initial camera position
    final currentLocation =
        await ref
            .read(liveTrackingRepositoryProvider)
            .getCurrentLocation();
    if (currentLocation != null && mounted) {
      final newCenter = LatLng(
        currentLocation.latitude,
        currentLocation.longitude,
      );
      setState(() {
        _center = newCenter;
      });

      // Add current location marker if no active session
      final liveTrackingState = ref.read(liveTrackingProvider);
      final session = liveTrackingState.currentSession;

      if (session == null ||
          session.status != WorkoutStatus.active ||
          session.trackingPoints.isEmpty) {
        _updateCurrentLocationMarker(newCenter, currentLocation, session);
      }

      // Programmatically move the map to the user's current location
      _animatedMove(newCenter, _zoom);
    } else {
      // Keep the default center but do not pretend it is a live location.
    }
  }

  void _onAcceptedLocationUpdate(
    TrackingPointEntity point,
    LiveTrackingState liveTrackingState,
  ) {
    if (_mapController == null) return;

    final newLatLng = LatLng(point.latitude, point.longitude);

    // Update current location marker
    _updateCurrentLocationMarker(
      newLatLng,
      point,
      liveTrackingState.currentSession,
    );

    // Follow current location only if following is enabled and user isn't interacting
    if (_isFollowing && !_manualByUser) {
      _animateToCurrentLocation(newLatLng);
    }
  }

  void _updateTrackingPath() {
    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    // If no session exists or session has ended, clear the map
    if (session == null || session.status == WorkoutStatus.completed) {
      _clearMapData();
      return;
    }

    if (session.status == WorkoutStatus.notStarted) {
      _clearMapData();
      return;
    }

    // If no tracking points, just clear polylines but keep current location marker
    if (session.trackingPoints.isEmpty) {
      _clearTrackingData();
      return;
    }

    // Build segments based on workout status changes
    final List<TrackingSegment> segments = LiveMapSegmentBuilder.buildSegments(
      session,
    );

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

    // Only add current location marker if there's no active tracking session
    // or if the session has no tracking points yet
    if (session != null &&
        session.status == WorkoutStatus.active &&
        session.trackingPoints.isNotEmpty) {
      // Don't show current location marker during active tracking
      // The activity-specific markers (start, current position) will be shown instead
      return;
    }

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
              color: Colors.black.withValues(alpha: 0.3),
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
              color: Colors.black.withValues(alpha: 0.3),
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
    _animatedMove(position, _zoom);
  }

  void _handleSessionStateChanges(WorkoutSessionEntity? currentSession) {
    final previousSession = _previousSession;
    if (previousSession != currentSession) {
      final routeOrStatusChanged =
          currentSession != null &&
          currentSession.status != WorkoutStatus.completed &&
          (previousSession == null ||
              previousSession.trackingPoints !=
                  currentSession.trackingPoints ||
              previousSession.status != currentSession.status);
      if (routeOrStatusChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _updateTrackingPath();
        });
      }
      if (previousSession != null &&
          (currentSession == null ||
              currentSession.status == WorkoutStatus.completed)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _clearMapData();
        });
      }

      _previousSession = currentSession;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final liveTrackingState = ref.watch(liveTrackingProvider);

        // Listen for error messages and show them in a SnackBar
        ref.listen<String?>(
          liveTrackingProvider.select((state) => state.errorMessage),
          (previous, next) {
            if (next != null) {
              _showErrorSnackBar(next);
              ref.read(liveTrackingProvider.notifier).clearErrorMessage();
            }
          },
        );
        ref.listen<TrackingPointEntity?>(
          liveTrackingProvider.select((state) => state.currentLocation),
          (previous, next) {
            if (next == null || next == previous) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _onAcceptedLocationUpdate(
                next,
                ref.read(liveTrackingProvider),
              );
            });
          },
        );

        // Check for session state changes
        _handleSessionStateChanges(liveTrackingState.currentSession);

        // Always use online flow - TileLayer will handle offline gracefully
        return Container(
          height: double.infinity, // Adjust height as needed
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radiusLg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
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
                    onMapEvent: (event) {
                      // Any user-driven map interaction disables following
                      // and marks manual control.
                      // We check for common interaction events and user source
                      final isUserEvent =
                          event.source != MapEventSource.mapController;
                      if (isUserEvent) {
                        _manualByUser = true;
                        _isFollowing = false;
                      }
                    },
                    onTap: (tapPosition, point) {
                      // Handle map tap if needed
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.github.cosmicsaurabh.rythmrun',
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
                              child: CupertinoActivityIndicator(),
                            ),
                            SizedBox(width: spacingSm),
                            Text('Loading location...'),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Error overlay is now handled by the SnackBar
              ],
            ),
          ),
        );
      },
    );
  }

  void _centerOnCurrentLocation() async {
    if (_mapController == null) {
      _showErrorSnackBar('Map not ready. Please try again.');
      return;
    }

    try {
      // Center button enables following and clears manual override
      _isFollowing = true;
      _manualByUser = false;
      final repository = ref.read(liveTrackingRepositoryProvider);

      // Check permissions first
      final permissionStatus = await repository.checkPermissions();
      if (!mounted) return;
      if (permissionStatus != LocationServiceStatus.granted) {
        _isFollowing = false;
        _showErrorSnackBar(
          LocationErrorHandler.getLocationErrorMessage(permissionStatus),
        );
        return;
      }

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: spacingSm),
              const Text('Getting your location...'),
            ],
          ),
          backgroundColor: CustomAppColors.statusInfo,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(spacingMd),
          duration: const Duration(seconds: 2),
        ),
      );

      final currentLocation = await repository.getCurrentLocation();
      if (!mounted) return;

      if (currentLocation != null) {
        final newLatLng = LatLng(
          currentLocation.latitude,
          currentLocation.longitude,
        );

        // Add current location marker (respects activity marker precedence)
        final liveTrackingState = ref.read(liveTrackingProvider);
        final session = liveTrackingState.currentSession;
        _updateCurrentLocationMarker(
          newLatLng,
          currentLocation,
          session, // Pass actual session to respect marker logic
        );

        // Center on location without changing zoom
        _animatedMove(newLatLng, _zoom);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Centered on your location'),
            backgroundColor: CustomAppColors.statusSuccess,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(spacingMd),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        _showErrorSnackBar(
          'Unable to get your current location. Please check your location settings.',
        );
      }
    } catch (_) {
      _showErrorSnackBar('Failed to get your location. Please try again.');
    }
  }

  void _fitTrackingPath() {
    // This is a user action, disable following
    _manualByUser = true;
    _isFollowing = false;

    final liveTrackingState = ref.read(liveTrackingProvider);
    final session = liveTrackingState.currentSession;

    if (session == null ||
        session.trackingPoints.isEmpty ||
        _mapController == null) {
      return;
    }

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

    final cameraFit = CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(50),
    );
    final camera = _mapController!.camera;
    final target = cameraFit.fit(camera);
    _animatedMove(target.center, target.zoom);
  }

  void _zoomIn() {
    // User action: disable following
    _manualByUser = true;
    _isFollowing = false;
    if (_mapController == null) return;
    final currentZoom = _mapController!.camera.zoom;
    _animatedMove(_mapController!.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    // User action: disable following
    _manualByUser = true;
    _isFollowing = false;
    if (_mapController == null) return;
    final currentZoom = _mapController!.camera.zoom;
    _animatedMove(_mapController!.camera.center, currentZoom - 1);
  }

  // Removed unused manual clear helper

  void _animatedMove(LatLng destLocation, double destZoom) {
    if (_mapController == null) return;

    // Stop any ongoing animation first
    _animationController.stop();
    _animationController.reset();

    final latTween = Tween<double>(
      begin: _mapController!.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController!.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController!.camera.zoom,
      end: destZoom,
    );

    final animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    );

    void listener() {
      _mapController!.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    }

    _animationController.addListener(listener);

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _animationController.removeListener(listener);
        _animationController.reset();

        // Ensure we're at the exact target location
        if (status == AnimationStatus.completed) {
          _mapController!.move(destLocation, destZoom);
        }
      }
    });

    _animationController.forward();
  }
}
