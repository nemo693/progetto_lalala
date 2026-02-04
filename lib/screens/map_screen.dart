import 'dart:async';
import 'dart:math' show Point;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../models/route.dart';
import '../models/waypoint.dart' as model;
import '../services/map_service.dart';
import '../services/location_service.dart';
import '../services/gpx_service.dart';
import '../services/route_storage_service.dart';
import 'routes_screen.dart';

/// Main screen — map fills the screen with minimal overlay controls.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapProvider = MapLibreProvider();
  final _locationService = LocationService();
  final _gpxService = GpxService();
  final _storage = RouteStorageService();
  final _recorder = TrackRecorder();

  StreamSubscription<Position>? _locationSub;
  Position? _currentPosition;
  String? _locationError;
  bool _styleLoaded = false;
  bool _followingUser = true;

  // Displayed route
  NavRoute? _activeRoute;
  List<model.Waypoint> _activeWaypoints = [];

  // Recording UI update timer
  Timer? _recordingTimer;

  // Default camera: centered on the Italian Alps (Dolomites area)
  static const _defaultLat = 46.5;
  static const _defaultLon = 11.35;
  static const _defaultZoom = 9.0;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final error = await _locationService.checkPermissions();
    if (error != null) {
      setState(() => _locationError = error);
      return;
    }

    // Get initial fix, then start streaming
    final pos = await _locationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _currentPosition = pos);
      _moveCameraToPosition(pos);
      _updateLocationMarker(pos);
    }

    await _locationService.startListening();
    _locationSub = _locationService.positionStream.listen(_onPositionUpdate);
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    setState(() {
      _currentPosition = pos;
      _locationError = null;
    });
    _updateLocationMarker(pos);
    if (_followingUser) {
      _moveCameraToPosition(pos);
    }

    // Feed GPS fixes to the recorder
    if (_recorder.state == RecordingState.recording) {
      _recorder.addPosition(pos);
    }
  }

  void _moveCameraToPosition(Position pos) {
    _mapProvider.setCamera(
      latitude: pos.latitude,
      longitude: pos.longitude,
      zoom: 15,
    );
  }

  void _updateLocationMarker(Position pos) {
    if (!_styleLoaded) return;
    _mapProvider.updateLocationMarker(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
    );
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapProvider.attach(controller);
  }

  void _onStyleLoaded() {
    setState(() => _styleLoaded = true);
    final pos = _currentPosition;
    if (pos != null) {
      _updateLocationMarker(pos);
    }
    // Re-display active route if style reloaded
    if (_activeRoute != null) {
      _displayRoute(_activeRoute!, _activeWaypoints);
    }
  }

  void _onCameraIdle() {
    _mapProvider.onCameraIdle();
  }

  void _zoomToLocation() async {
    setState(() => _followingUser = true);
    final pos = _currentPosition;
    if (pos != null) {
      _moveCameraToPosition(pos);
    } else {
      final fresh = await _locationService.getCurrentPosition();
      if (fresh != null && mounted) {
        setState(() => _currentPosition = fresh);
        _moveCameraToPosition(fresh);
        _updateLocationMarker(fresh);
      }
    }
  }

  void _resetNorth() {
    _mapProvider.resetNorth();
  }

  // ── GPX Import ─────────────────────────────────────────────────────────

  Future<void> _importGpx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      final imported = await _gpxService.importFromFile(path);
      await _storage.saveRoute(imported.route, imported.waypoints);
      _showRoute(imported.route, imported.waypoints);
    } catch (e) {
      if (mounted) {
        setState(() => _locationError = 'Failed to import GPX: $e');
        // Clear error after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _locationError = null);
        });
      }
    }
  }

  void _showRoute(NavRoute route, List<model.Waypoint> waypoints) {
    // Remove previous route display
    _clearRouteDisplay();

    setState(() {
      _activeRoute = route;
      _activeWaypoints = waypoints;
    });

    if (_styleLoaded) {
      _displayRoute(route, waypoints);
    }
  }

  Future<void> _displayRoute(
      NavRoute route, List<model.Waypoint> waypoints) async {
    // Draw track polyline
    await _mapProvider.addTrackLayer('active_route', route.coordinatePairs);

    // Draw waypoint markers
    if (waypoints.isNotEmpty) {
      await _mapProvider.addWaypointMarkers(
        'active_waypoints',
        waypoints
            .map((w) => {
                  'lat': w.latitude,
                  'lon': w.longitude,
                  'name': w.name,
                })
            .toList(),
      );
    }

    // Zoom to fit the route
    if (route.points.length >= 2) {
      _zoomToRoute(route);
    }
  }

  void _zoomToRoute(NavRoute route) {
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final pt in route.points) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLon) minLon = pt.longitude;
      if (pt.longitude > maxLon) maxLon = pt.longitude;
    }

    final controller = _mapProvider.controller;
    if (controller != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLon),
            northeast: LatLng(maxLat, maxLon),
          ),
          left: 40,
          top: 80,
          right: 40,
          bottom: 80,
        ),
      );
    }
  }

  void _clearRouteDisplay() {
    if (_activeRoute != null) {
      _mapProvider.removeLayer('active_route');
      _mapProvider.removeWaypointMarkers('active_waypoints');
      setState(() {
        _activeRoute = null;
        _activeWaypoints = [];
      });
    }
  }

  // ── Routes list ────────────────────────────────────────────────────────

  Future<void> _openRoutesList() async {
    final selectedRoute = await Navigator.push<NavRoute>(
      context,
      MaterialPageRoute(builder: (_) => const RoutesScreen()),
    );

    if (selectedRoute != null && mounted) {
      // Load full route with waypoints
      final loaded = await _storage.loadRoute(selectedRoute.id);
      if (loaded != null) {
        _showRoute(loaded.route, loaded.waypoints);
      } else {
        _showRoute(selectedRoute, []);
      }
    }
  }

  // ── Recording ──────────────────────────────────────────────────────────

  void _toggleRecording() {
    switch (_recorder.state) {
      case RecordingState.idle:
        _startRecording();
      case RecordingState.recording:
        _pauseRecording();
      case RecordingState.paused:
        _showRecordingActions();
    }
  }

  void _startRecording() {
    // Switch to high-accuracy GPS for recording
    _locationService.stopListening();
    _locationService.startListening(highAccuracy: true, distanceFilter: 3);

    _recorder.start();
    // Update recording stats display every second
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
    setState(() {});
  }

  void _pauseRecording() {
    _recorder.pause();
    setState(() {});
  }

  void _resumeRecording() {
    _recorder.resume();
    setState(() {});
  }

  void _showRecordingActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('Resume', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                _resumeRecording();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop, color: Colors.red),
              title: const Text('Stop & Save', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                _stopAndSaveRecording();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.white38),
              title: const Text('Discard', style: TextStyle(color: Colors.white38)),
              onTap: () {
                Navigator.pop(ctx);
                _discardRecording();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopAndSaveRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final points = _recorder.stop();
    if (points.length < 2) {
      setState(() {});
      return;
    }

    // Ask for a name
    final name = await _promptRouteName();
    if (name == null || name.isEmpty) {
      // Save with default name
      final route = NavRoute.fromPoints(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Track ${DateTime.now().toString().substring(0, 16)}',
        points: List.of(points),
        source: RouteSource.recorded,
      );
      await _storage.saveRoute(route);
      _showRoute(route, []);
    } else {
      final route = NavRoute.fromPoints(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        points: List.of(points),
        source: RouteSource.recorded,
      );
      await _storage.saveRoute(route);
      _showRoute(route, []);
    }

    // Switch back to normal GPS
    _locationService.stopListening();
    _locationService.startListening();
    setState(() {});
  }

  void _discardRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recorder.stop();

    // Switch back to normal GPS
    _locationService.stopListening();
    _locationService.startListening();
    setState(() {});
  }

  Future<String?> _promptRouteName() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Save track', style: TextStyle(color: Colors.white70)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white70),
          decoration: const InputDecoration(
            hintText: 'Track name',
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _locationSub?.cancel();
    _locationService.dispose();
    _mapProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _recorder.state != RecordingState.idle;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────
          MapLibreMap(
            styleString: MapLibreProvider.defaultStyleUrl,
            initialCameraPosition: const CameraPosition(
              target: LatLng(_defaultLat, _defaultLon),
              zoom: _defaultZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: _onCameraIdle,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            compassEnabled: false,
            myLocationEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            attributionButtonMargins: const Point(8, 8),
          ),

          // ── Controls: top-right ─────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: Column(
              children: [
                _ControlButton(
                  icon: Icons.navigation,
                  tooltip: 'Reset north',
                  onPressed: _resetNorth,
                ),
                const SizedBox(height: 8),
                _ControlButton(
                  icon: Icons.my_location,
                  tooltip: 'Zoom to location',
                  onPressed: _zoomToLocation,
                ),
                const SizedBox(height: 8),
                _ControlButton(
                  icon: Icons.folder_open,
                  tooltip: 'Import GPX',
                  onPressed: _importGpx,
                ),
                const SizedBox(height: 8),
                _ControlButton(
                  icon: Icons.list,
                  tooltip: 'Routes',
                  onPressed: _openRoutesList,
                ),
              ],
            ),
          ),

          // ── Recording button: top-left ─────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: _RecordButton(
              state: _recorder.state,
              onPressed: _toggleRecording,
            ),
          ),

          // ── Recording stats bar ────────────────────────────
          if (isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 68,
              left: 12,
              child: _RecordingStatsBar(recorder: _recorder),
            ),

          // ── Active route info: bottom-left ─────────────────
          if (_activeRoute != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 12,
              child: _RouteInfoChip(
                route: _activeRoute!,
                onClose: _clearRouteDisplay,
              ),
            ),

          // ── Coordinate display: bottom-right ────────────────
          if (_currentPosition != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              right: 12,
              child: _CoordinateChip(position: _currentPosition!),
            ),

          // ── Location error: top-center ──────────────────────
          if (_locationError != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 56,
              right: 56,
              child: _ErrorBanner(message: _locationError!),
            ),
        ],
      ),
    );
  }
}

// ── Small UI components ───────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: Colors.white70, size: 24),
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onPressed;

  const _RecordButton({required this.state, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    IconData icon;
    String tooltip;

    switch (state) {
      case RecordingState.idle:
        bgColor = Colors.black54;
        icon = Icons.fiber_manual_record;
        tooltip = 'Start recording';
      case RecordingState.recording:
        bgColor = Colors.red.shade800;
        icon = Icons.pause;
        tooltip = 'Pause recording';
      case RecordingState.paused:
        bgColor = Colors.orange.shade800;
        icon = Icons.more_horiz;
        tooltip = 'Recording paused';
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: Colors.white70, size: 24),
          ),
        ),
      ),
    );
  }
}

class _RecordingStatsBar extends StatelessWidget {
  final TrackRecorder recorder;

  const _RecordingStatsBar({required this.recorder});

  @override
  Widget build(BuildContext context) {
    final dist = (recorder.distance / 1000).toStringAsFixed(2);
    final gain = recorder.elevationGain.round();
    final elapsed = recorder.elapsed;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    final time = h > 0
        ? '${h}h${m.toString().padLeft(2, '0')}m'
        : '$m:${s.toString().padLeft(2, '0')}';
    final pts = recorder.pointCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$dist km  +${gain}m  $time  ${pts}pt',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _RouteInfoChip extends StatelessWidget {
  final NavRoute route;
  final VoidCallback onClose;

  const _RouteInfoChip({required this.route, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final distKm = (route.distance / 1000).toStringAsFixed(1);
    final gain = route.elevationGain.round();
    final loss = route.elevationLoss.round();

    return Container(
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6, right: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                route.name,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$distKm km  +${gain}m  -${loss}m',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, color: Colors.white38, size: 16),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateChip extends StatelessWidget {
  final Position position;

  const _CoordinateChip({required this.position});

  @override
  Widget build(BuildContext context) {
    final lat = position.latitude.toStringAsFixed(5);
    final lon = position.longitude.toStringAsFixed(5);
    final alt = position.altitude.round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$lat, $lon  ${alt}m',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withAlpha(200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}
