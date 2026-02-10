import 'dart:async';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../main.dart' show offlineManager;
import '../models/route.dart';
import '../models/waypoint.dart' as model;
import '../services/connectivity_service.dart';
import '../services/download_foreground_service.dart';
import '../services/map_service.dart';
import '../services/location_service.dart';
import '../services/gpx_service.dart';
import '../services/offline_manager.dart';
import '../services/route_storage_service.dart';
import '../utils/tile_calculator.dart';
import '../widgets/download_progress_overlay.dart';
import 'offline_regions_screen.dart';
import 'routes_screen.dart';

/// Main screen — map fills the screen with minimal overlay controls.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _mapProvider = MapLibreProvider();
  final _locationService = LocationService();
  final _storage = RouteStorageService();
  final _recorder = TrackRecorder();
  final _connectivityService = ConnectivityService();

  StreamSubscription<Position>? _locationSub;
  StreamSubscription<bool>? _connectivitySub;
  Position? _currentPosition;
  String? _locationError;
  bool _styleLoaded = false;
  bool _followingUser = true;
  bool _isOnline = true;

  // Displayed route
  NavRoute? _activeRoute;
  List<model.Waypoint> _activeWaypoints = [];

  // Recording UI update timer
  Timer? _recordingTimer;

  // Offline download state
  Stream<DownloadProgress>? _downloadStream;
  StreamSubscription<DownloadProgress>? _downloadProgressSub;
  bool _isDownloading = false;

  // Default camera: centered on the Italian Alps (Dolomites area)
  static const _defaultLat = 46.5;
  static const _defaultLon = 11.35;
  static const _defaultZoom = 9.0;

  // Track last camera position so rebuilds don't reset the map view
  CameraPosition _lastCameraPosition = const CameraPosition(
    target: LatLng(_defaultLat, _defaultLon),
    zoom: _defaultZoom,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
    _initConnectivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app comes back to the foreground, refresh the UI with the
    // latest position the foreground service may have delivered while
    // backgrounded.  The position stream keeps firing (foreground service),
    // but setState calls are no-ops while the widget tree is inactive, so
    // the map and stats may be stale.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      final pos = _currentPosition;
      if (pos != null) {
        _updateLocationMarker(pos);
        if (_followingUser) _moveCameraToPosition(pos);
      }
    }
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

  Future<void> _initConnectivity() async {
    await _connectivityService.initialize();
    if (mounted) {
      setState(() => _isOnline = _connectivityService.isOnline);
    }
    _connectivitySub = _connectivityService.onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
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

    // Feed GPS fixes to the recorder and update the live track on the map
    if (_recorder.state == RecordingState.recording) {
      final accepted = _recorder.addPosition(pos);
      if (accepted && _recorder.points.length >= 2) {
        _mapProvider.addTrackLayer(
          'recording',
          _recorder.points
              .map((p) => [p.latitude, p.longitude])
              .toList(),
        );
      }
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
    // Style reload invalidates all map objects — clear stale references
    _mapProvider.clearLocationMarkerRefs();
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
    // Remember camera position so widget rebuilds don't reset the view
    final cam = _mapProvider.controller?.cameraPosition;
    if (cam != null) {
      _lastCameraPosition = cam;
    }
    // Disable auto-follow if user manually moved the camera
    // (camera moves from position updates don't count)
    if (_followingUser && _currentPosition != null) {
      final controller = _mapProvider.controller;
      if (controller != null) {
        final cameraPos = controller.cameraPosition;
        if (cameraPos != null) {
          final userLat = _currentPosition!.latitude;
          final userLon = _currentPosition!.longitude;
          final cameraLat = cameraPos.target.latitude;
          final cameraLon = cameraPos.target.longitude;

          // If camera is more than ~100m away from user position, disable follow
          final distLat = (cameraLat - userLat).abs();
          final distLon = (cameraLon - userLon).abs();
          if (distLat > 0.001 || distLon > 0.001) {
            setState(() => _followingUser = false);
          }
        }
      }
    }
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
      // Nudge the camera to force MapLibre to redraw after layer removal,
      // otherwise the track visually lingers until the next user interaction.
      final controller = _mapProvider.controller;
      if (controller != null) {
        final cam = controller.cameraPosition;
        if (cam != null) {
          controller.moveCamera(CameraUpdate.newLatLng(cam.target));
        }
      }
      // Disable auto-follow so the camera stays where it is instead of
      // snapping back to the user's GPS position on the next location update.
      setState(() {
        _activeRoute = null;
        _activeWaypoints = [];
        _followingUser = false;
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
    // Switch to high-accuracy GPS with foreground service for recording.
    // The foreground service keeps GPS alive when the app is backgrounded.
    _locationService.stopListening();
    _locationService.startListening(
      highAccuracy: true,
      distanceFilter: 3,
      foreground: true,
    );

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

    // Remove the live recording track layer
    _mapProvider.removeLayer('recording');

    final points = _recorder.stop();
    if (points.length < 2) {
      if (mounted) {
        setState(() => _locationError = 'Track too short (need at least 2 points)');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _locationError = null);
        });
      }
      setState(() {});
      return;
    }

    try {
      // Ask for a name
      String? name;
      if (mounted) {
        name = await _promptRouteName();
      }

      // Create route with user-provided name or default
      final routeName = (name != null && name.isNotEmpty)
          ? name
          : 'Track ${DateTime.now().toString().substring(0, 16)}';

      final route = NavRoute.fromPoints(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: routeName,
        points: List.of(points),
        source: RouteSource.recorded,
      );

      // Save to storage
      await _storage.saveRoute(route);

      // Display on map
      if (mounted) {
        _showRoute(route, []);
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Failed to save track';
        if (e.toString().contains('Permission')) {
          errorMsg = 'Storage permission denied. Check app settings.';
        } else if (e.toString().contains('FileSystemException')) {
          errorMsg = 'Could not save file. Check storage space.';
        } else {
          errorMsg = 'Failed to save: ${e.toString().split('\n').first}';
        }

        setState(() => _locationError = errorMsg);
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) setState(() => _locationError = null);
        });
      }
    } finally {
      // Always switch back to normal GPS
      _locationService.stopListening();
      _locationService.startListening();
      if (mounted) setState(() {});
    }
  }

  void _discardRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _mapProvider.removeLayer('recording');
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

  // ── Offline Download ─────────────────────────────────────────────────

  void _showDownloadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_square, color: Colors.white70),
              title: const Text('Download visible area',
                  style: TextStyle(color: Colors.white70)),
              subtitle: const Text('Save current map view for offline use',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _configureVisibleAreaDownload();
              },
            ),
            if (_activeRoute != null)
              ListTile(
                leading: const Icon(Icons.route, color: Colors.white70),
                title: const Text('Download around route',
                    style: TextStyle(color: Colors.white70)),
                subtitle: Text(
                    'Save tiles along ${_activeRoute!.name}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _configureRouteDownload();
                },
              ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.white70),
              title: const Text('Manage offline regions',
                  style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                _openRegionsScreen();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _configureVisibleAreaDownload() async {
    final controller = _mapProvider.controller;
    if (controller == null) return;

    // Get the actual visible bounds from the map controller
    final visibleRegion = await controller.getVisibleRegion();
    final bounds = BoundingBox(
      minLat: visibleRegion.southwest.latitude,
      minLon: visibleRegion.southwest.longitude,
      maxLat: visibleRegion.northeast.latitude,
      maxLon: visibleRegion.northeast.longitude,
    );

    _showDownloadConfigDialog(
      bounds: bounds,
      suggestedName: 'Map ${DateTime.now().toString().substring(0, 10)}',
    );
  }

  void _configureRouteDownload() {
    if (_activeRoute == null) return;

    final bbox = computeRouteBBox(_activeRoute!.coordinatePairs);
    if (bbox == null) return;

    final buffered = computeBufferedBBox(bbox, 5000); // 5km buffer

    _showDownloadConfigDialog(
      bounds: buffered,
      suggestedName: _activeRoute!.name,
    );
  }

  void _showDownloadConfigDialog({
    required BoundingBox bounds,
    required String suggestedName,
  }) {
    final nameController = TextEditingController(text: suggestedName);
    int minZoom = 10;
    int maxZoom = 15;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final tileCount = offlineManager.estimateTileCount(
            bounds, minZoom, maxZoom,
          );
          final sizeEstimate = formatBytes(
            offlineManager.estimateSize(tileCount),
          );

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('Download offline map',
                style: TextStyle(color: Colors.white70)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: 'Region name',
                    labelStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Min zoom: $minZoom',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Slider(
                  value: minZoom.toDouble(),
                  min: 6,
                  max: maxZoom.toDouble(),
                  divisions: maxZoom - 6,
                  label: '$minZoom',
                  onChanged: (v) =>
                      setDialogState(() => minZoom = v.round()),
                ),
                Text('Max zoom: $maxZoom',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Slider(
                  value: maxZoom.toDouble(),
                  min: minZoom.toDouble(),
                  max: 16,
                  divisions: 16 - minZoom,
                  label: '$maxZoom',
                  onChanged: (v) =>
                      setDialogState(() => maxZoom = v.round()),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('~$tileCount tiles',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                      Text('~$sizeEstimate',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ],
                  ),
                ),
                if (tileCount > 10000)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Large download. Consider reducing zoom range.',
                      style: TextStyle(
                          color: Colors.orange.shade300, fontSize: 11),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _startDownload(
                    name: nameController.text.isNotEmpty
                        ? nameController.text
                        : suggestedName,
                    bounds: bounds,
                    minZoom: minZoom,
                    maxZoom: maxZoom,
                  );
                },
                child: const Text('Download'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startDownload({
    required String name,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
  }) async {
    // Start foreground service so download survives screen-off / app switch
    await DownloadForegroundService.start();

    final stream = offlineManager.downloadRegion(
      regionName: name,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    final broadcastStream = stream.asBroadcastStream();

    // Listen to progress to update the foreground notification
    _downloadProgressSub = broadcastStream.listen((progress) {
      DownloadForegroundService.updateProgress(progress.progressPercent);
      if (progress.isComplete) {
        _downloadProgressSub?.cancel();
        _downloadProgressSub = null;
        DownloadForegroundService.stop();
      }
    });

    setState(() {
      _downloadStream = broadcastStream;
      _isDownloading = true;
    });
  }

  void _cancelDownload() {
    _downloadProgressSub?.cancel();
    _downloadProgressSub = null;
    DownloadForegroundService.stop();
    setState(() {
      _downloadStream = null;
      _isDownloading = false;
    });
  }

  void _onDownloadComplete() {
    // Foreground service already stopped by the progress listener
    setState(() {
      _downloadStream = null;
      _isDownloading = false;
    });
  }

  Future<void> _openRegionsScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OfflineRegionsScreen()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _locationSub?.cancel();
    _connectivitySub?.cancel();
    _downloadProgressSub?.cancel();
    _locationService.dispose();
    _connectivityService.dispose();
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
            initialCameraPosition: _lastCameraPosition,
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
                  tooltip: _followingUser ? 'Following location' : 'Zoom to location',
                  onPressed: _zoomToLocation,
                  isActive: _followingUser,
                ),
                const SizedBox(height: 8),
                _ControlButton(
                  icon: Icons.list,
                  tooltip: 'Routes',
                  onPressed: _openRoutesList,
                ),
                const SizedBox(height: 8),
                _ControlButton(
                  icon: Icons.cloud_download,
                  tooltip: 'Offline maps',
                  onPressed: _showDownloadOptions,
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

          // ── Offline indicator: top-left ──────────────────────
          if (!_isOnline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 68,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900.withAlpha(200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, color: Colors.white70, size: 14),
                    SizedBox(width: 4),
                    Text('Offline',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),

          // ── Download progress overlay ──────────────────────
          if (_isDownloading && _downloadStream != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 12,
              right: 68,
              child: DownloadProgressOverlay(
                progressStream: _downloadStream!,
                onCancel: _cancelDownload,
                onComplete: _onDownloadComplete,
              ),
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
  final bool isActive;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: isActive ? const Color(0xFF4A90D9) : Colors.black54,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: tooltip,
            child: Icon(
              icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 24,
            ),
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
    final loss = recorder.elevationLoss.round();
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
        '$dist km  +${gain}m  -${loss}m  $time  ${pts}pt',
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
    // Leave room for right-side controls and padding
    final maxWidth = MediaQuery.of(context).size.width - 80;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6, right: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
