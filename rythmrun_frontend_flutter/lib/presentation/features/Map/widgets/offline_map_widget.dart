// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
// import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
// import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_feed_helper.dart';
// import 'package:rythmrun_frontend_flutter/presentation/features/Map/screens/live_map_segment_builder.dart';
// import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

// class OfflineMapWidget extends StatefulWidget {
//   final WorkoutSessionEntity? workout;
//   final List<Marker> markers;
//   final MapController? mapController;
//   final LatLng center;
//   final double zoom;
//   final VoidCallback? onMapReady;

//   const OfflineMapWidget({
//     super.key,
//     required this.workout,
//     required this.markers,
//     required this.mapController,
//     required this.center,
//     required this.zoom,
//     this.onMapReady,
//   });

//   @override
//   State<OfflineMapWidget> createState() => _OfflineMapWidgetState();
// }

// class _OfflineMapWidgetState extends State<OfflineMapWidget> {
//   final List<Polyline> _solidPolylines = [];
//   final List<Polyline> _dashedPolylines = [];

//   @override
//   void initState() {
//     super.initState();
//     _buildOfflineVisualization();
//   }

//   @override
//   void didUpdateWidget(OfflineMapWidget oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (widget.workout != oldWidget.workout) {
//       _buildOfflineVisualization();
//     }
//   }

//   void _buildOfflineVisualization() {
//     _solidPolylines.clear();
//     _dashedPolylines.clear();

//     if (widget.workout?.trackingPoints.isEmpty ?? true) return;

//     final segments = LiveMapSegmentBuilder.buildSegments(widget.workout!);

//     for (final segment in segments) {
//       if (segment.points.length < 2) continue;

//       final points =
//           segment.points
//               .map((point) => LatLng(point.latitude, point.longitude))
//               .toList();

//       final polyline = Polyline(
//         points: points,
//         strokeWidth: 4.0,
//         color:
//             segment.status == WorkoutStatus.active
//                 ? getWorkoutColor(widget.workout!.type)
//                 : getWorkoutColor(widget.workout!.type).withOpacity(0.5),
//         pattern:
//             segment.status == WorkoutStatus.paused
//                 ? StrokePattern.dashed(segments: [10, 5])
//                 : const StrokePattern.solid(),
//       );

//       if (segment.status == WorkoutStatus.active) {
//         _solidPolylines.add(polyline);
//       } else {
//         _dashedPolylines.add(polyline);
//       }
//     }

//     setState(() {});
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Debug: Print offline mode status
//     print('🗺️ OfflineMapWidget: Building with workout: ${widget.workout?.id}');
//     print('🗺️ OfflineMapWidget: Markers count: ${widget.markers.length}');
//     print(
//       '🗺️ OfflineMapWidget: Polylines - solid: ${_solidPolylines.length}, dashed: ${_dashedPolylines.length}',
//     );

//     return Container(
//       decoration: BoxDecoration(
//         color: const Color.fromARGB(255, 229, 35, 35),
//         borderRadius: BorderRadius.circular(radiusLg),
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(radiusLg),
//         child: Stack(
//           children: [
//             // Grid background for better visual reference
//             CustomPaint(painter: GridPainter(), child: Container()),

//             // Map without tiles
//             FlutterMap(
//               mapController: widget.mapController,
//               options: MapOptions(
//                 initialCenter: widget.center,
//                 initialZoom: widget.zoom,
//                 minZoom: 10,
//                 maxZoom: 18,
//                 backgroundColor: const Color.fromARGB(209, 0, 0, 0),
//                 onMapReady: widget.onMapReady,
//               ),
//               children: [
//                 // No TileLayer - this is the key difference
//                 PolylineLayer(polylines: _solidPolylines),
//                 PolylineLayer(polylines: _dashedPolylines),
//                 MarkerLayer(markers: widget.markers),
//               ],
//             ),

//             // Offline indicator
//             Positioned(
//               top: 16,
//               right: 16,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: Colors.orange.shade100,
//                   borderRadius: BorderRadius.circular(24),
//                   border: Border.all(color: Colors.orange.shade300),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(
//                       Icons.map_outlined,
//                       size: 16,
//                       color: Colors.orange.shade700,
//                     ),
//                     const SizedBox(width: 4),
//                     Text(
//                       'Offline Mode',
//                       style: TextStyle(
//                         fontSize: 12,
//                         color: Colors.orange.shade700,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class GridPainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint =
//         Paint()
//           ..color = Colors.white.withOpacity(
//             0.3,
//           ) // White lines visible on red background
//           ..strokeWidth = 1;

//     const double gridSize = 20.0;

//     // Draw vertical lines
//     for (double x = 0; x <= size.width; x += gridSize) {
//       canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
//     }

//     // Draw horizontal lines
//     for (double y = 0; y <= size.height; y += gridSize) {
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }
