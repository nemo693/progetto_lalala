import 'dart:async';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../main.dart' show offlineManager;
import '../models/map_source.dart';
import '../models/route.dart';
import '../models/waypoint.dart' as model;
import '../services/connectivity_service.dart';
import '../services/download_foreground_service.dart';
import '../services/map_service.dart';
import '../services/map_source_preference.dart';
import '../services/location_service.dart';
import '../services/gpx_service.dart';
import '../services/offline_manager.dart';
import '../services/route_storage_service.dart';
import '../services/wms_tile_server.dart';
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

  // Map source
  MapSource _currentMapSource = MapSource.openFreeMap;

  // Offline download state
  Stream<DownloadProgress>? _downloadStream;
  StreamSubscription<DownloadProgress>? _downloadProgressSub;
  bool _isDownloading = false;

  // Show offline region boundaries on the map
  bool _showRegionBoundaries = false;

  // Resolved style string for WMS sources (needs tile server port).
  // For non-WMS sources this is null and we use source.styleString directly.
  String? _wmsResolvedStyle;

  // True while a programmatic camera move is in flight (GPS follow, zoom-to-route, etc.).
  // Used to distinguish user-initiated pans from code-initiated moves in _onCameraIdle.
  bool _programmaticMove = false;

  // Default camera: centered on the Italian Alps (Dolomites area)
  static const _defaultLat = 46.5;
  static const _defaultLon = 11.35;
  static const _defaultZoom = 9.0;

  // Rectangle drawing for offline download
  bool _isDrawingRectangle = false;
  LatLng? _rectangleStart;
  LatLng? _rectangleEnd;
  Fill? _rectangleFill;

  // Track last camera position so rebuilds don't reset the map view
  CameraPosition _lastCameraPosition = const CameraPosition(
    target: LatLng(_defaultLat, _defaultLon),
    zoom: _defaultZoom,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMapSourcePreference();
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

  Future<void> _loadMapSourcePreference() async {
    final source = await MapSourcePreference.load();
    if (mounted && source.id != _currentMapSource.id) {
      // For WMS sources, start the tile server to resolve the style
      String? resolvedWmsStyle;
      if (source.type == MapSourceType.wms) {
        final port = await WmsTileServer.start();
        WmsTileServer.registerSource(source);
        resolvedWmsStyle = source.wmsStyleString(port);
      }
      _mapProvider.setCurrentSource(source);
      setState(() {
        _currentMapSource = source;
        _wmsResolvedStyle = resolvedWmsStyle;
      });
    }
  }

  Future<void> _switchMapSource(MapSource source) async {
    if (source.id == _currentMapSource.id) return;

    // For WMS sources, start the tile server and resolve the style
    String? resolvedWmsStyle;
    if (source.type == MapSourceType.wms) {
      final port = await WmsTileServer.start();
      WmsTileServer.registerSource(source);
      resolvedWmsStyle = source.wmsStyleString(port);
    }

    _mapProvider.clearLocationMarkerRefs();
    _mapProvider.setCurrentSource(source);
    setState(() {
      _currentMapSource = source;
      _wmsResolvedStyle = resolvedWmsStyle;
      _styleLoaded = false;
    });
    MapSourcePreference.save(source);
    // Region boundaries are redrawn in _onStyleLoaded after the new style loads
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
    _programmaticMove = true;
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
    // Re-display region boundaries if they were showing
    if (_showRegionBoundaries) {
      _loadRegionBoundaries();
    }
  }

  void _onCameraIdle() {
    _mapProvider.onCameraIdle();
    // Remember camera position so widget rebuilds don't reset the view
    final cam = _mapProvider.controller?.cameraPosition;
    if (cam != null) {
      _lastCameraPosition = cam;
    }
    // If the camera move was programmatic (GPS follow, zoom-to-route, etc.)
    // just clear the flag and don't touch follow mode.
    if (_programmaticMove) {
      _programmaticMove = false;
      return;
    }
    // User-initiated pan/zoom — disable auto-follow so the map stays put.
    if (_followingUser) {
      setState(() => _followingUser = false);
    }
  }

  void _onMapClick(Point<double> point, LatLng latLng) {
    if (_isDrawingRectangle) {
      if (_rectangleStart == null) {
        // First click: set start point
        setState(() => _rectangleStart = latLng);
      } else {
        // Second click: set end point and show preview
        setState(() => _rectangleEnd = latLng);
        _drawRectanglePreview();
      }
    }
  }

  void _onMapLongClick(Point<double> point, LatLng latLng) {
    // Long press cancels rectangle drawing
    if (_isDrawingRectangle) {
      _cancelRectangleDrawing();
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
    _programmaticMove = true;
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
      _programmaticMove = true;
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

  void _showLayersAndDownloadSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // ── Map source section ──
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 4),
              child: Text('MAP SOURCE',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
            ),
            ...MapSource.all.map((source) {
              final isActive = source.id == _currentMapSource.id;
              IconData icon;
              if (source.type == MapSourceType.vector) {
                icon = Icons.map;
              } else if (source.type == MapSourceType.wms) {
                icon = Icons.photo_library;
              } else if (source.id == 'esri_imagery') {
                icon = Icons.satellite_alt;
              } else {
                icon = Icons.terrain;
              }
              return ListTile(
                leading: Icon(
                  icon,
                  color: isActive
                      ? const Color(0xFF4A90D9)
                      : Colors.white70,
                ),
                title: Text(source.name,
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF4A90D9)
                          : Colors.white70,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    )),
                trailing: isActive
                    ? const Icon(Icons.check,
                        color: Color(0xFF4A90D9), size: 20)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchMapSource(source);
                },
              );
            }),

            const Divider(color: Colors.white12),

            // ── Offline section ──
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 4),
              child: Text('OFFLINE',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
            ),
            ListTile(
              leading: Icon(
                Icons.grid_on,
                color: _showRegionBoundaries
                    ? const Color(0xFF4A90D9)
                    : Colors.white70,
              ),
              title: Text('Show downloaded regions',
                  style: TextStyle(
                    color: _showRegionBoundaries
                        ? const Color(0xFF4A90D9)
                        : Colors.white70,
                  )),
              trailing: _showRegionBoundaries
                  ? const Icon(Icons.check,
                      color: Color(0xFF4A90D9), size: 20)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _toggleRegionBoundaries();
              },
            ),
            ListTile(
              leading: const Icon(Icons.crop_square, color: Colors.white70),
              title: const Text('Draw area to download',
                  style: TextStyle(color: Colors.white70)),
              subtitle: const Text('Drag a rectangle on the map',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _startDrawingRectangle();
              },
            ),
            if (_activeRoute != null)
              ListTile(
                leading: const Icon(Icons.route, color: Colors.white70),
                title: const Text('Download around route',
                    style: TextStyle(color: Colors.white70)),
                subtitle: Text(
                    'Save tiles along ${_activeRoute!.name}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _configureRouteDownload();
                },
              ),
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
      ),
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

  void _startDrawingRectangle() {
    setState(() {
      _isDrawingRectangle = true;
      _rectangleStart = null;
      _rectangleEnd = null;
    });
    _showRectangleInstructions();
  }

  void _showRectangleInstructions() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tap two corners to draw download area. Long-press to cancel.',
          style: TextStyle(fontSize: 13),
        ),
        backgroundColor: const Color(0xFF4A90D9),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  void _cancelRectangleDrawing() {
    setState(() {
      _isDrawingRectangle = false;
      _rectangleStart = null;
      _rectangleEnd = null;
    });
    _removeRectanglePreview();
  }

  Future<void> _drawRectanglePreview() async {
    final start = _rectangleStart;
    final end = _rectangleEnd;
    if (start == null || end == null) return;

    final controller = _mapProvider.controller;
    if (controller == null) return;

    // Remove old rectangle if any
    _removeRectanglePreview();

    // Draw semi-transparent rectangle fill
    final corners = [
      LatLng(start.latitude, start.longitude),
      LatLng(start.latitude, end.longitude),
      LatLng(end.latitude, end.longitude),
      LatLng(end.latitude, start.longitude),
      LatLng(start.latitude, start.longitude), // close the polygon
    ];

    _rectangleFill = await controller.addFill(
      FillOptions(
        geometry: [corners],
        fillColor: '#4A90D9',
        fillOpacity: 0.2,
        fillOutlineColor: '#4A90D9',
      ),
    );

    // Show confirm/cancel dialog
    _showRectangleConfirmDialog();
  }

  void _removeRectanglePreview() {
    final controller = _mapProvider.controller;
    final fill = _rectangleFill;
    if (controller != null && fill != null) {
      controller.removeFill(fill);
      _rectangleFill = null;
    }
  }

  void _showRectangleConfirmDialog() {
    final start = _rectangleStart;
    final end = _rectangleEnd;
    if (start == null || end == null) return;

    final bounds = BoundingBox(
      minLat: start.latitude < end.latitude ? start.latitude : end.latitude,
      maxLat: start.latitude > end.latitude ? start.latitude : end.latitude,
      minLon: start.longitude < end.longitude ? start.longitude : end.longitude,
      maxLon: start.longitude > end.longitude ? start.longitude : end.longitude,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Download this area?',
            style: TextStyle(color: Colors.white70)),
        content: Text(
          'Area: ${bounds.minLat.toStringAsFixed(4)}, ${bounds.minLon.toStringAsFixed(4)} → ${bounds.maxLat.toStringAsFixed(4)}, ${bounds.maxLon.toStringAsFixed(4)}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelRectangleDrawing();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeRectanglePreview();
              setState(() {
                _isDrawingRectangle = false;
                _rectangleStart = null;
                _rectangleEnd = null;
              });
              _showDownloadConfigDialog(
                bounds: bounds,
                suggestedName: 'Area ${DateTime.now().toString().substring(0, 10)}',
              );
            },
            child: const Text('Configure'),
          ),
        ],
      ),
    );
  }

  void _showDownloadConfigDialog({
    required BoundingBox bounds,
    required String suggestedName,
  }) {
    final nameController = TextEditingController(text: suggestedName);
    int minZoom = 10;
    int maxZoom = 15;
    // Default to current source if it supports offline, otherwise OpenFreeMap
    final initialSource = _currentMapSource.supportsOfflineDownload
        ? _currentMapSource.id
        : MapSource.openFreeMap.id;
    final selectedSourceIds = <String>{initialSource};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final tilesPerSource = offlineManager.estimateTileCount(
            bounds, minZoom, maxZoom,
          );
          int totalBytes = 0;
          for (final srcId in selectedSourceIds) {
            final src = MapSource.byId(srcId);
            totalBytes += offlineManager.estimateSize(
              tilesPerSource,
              bytesPerTile: src.avgTileSizeBytes,
            );
          }
          final totalTiles = tilesPerSource * selectedSourceIds.length;
          final sizeEstimate = formatBytes(totalBytes);

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text('Download offline map',
                style: TextStyle(color: Colors.white70)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white70),
                    decoration: const InputDecoration(
                      labelText: 'Region name',
                      labelStyle: TextStyle(color: Colors.white38),
                      hintText: 'e.g. Dolomiti West',
                      hintStyle: TextStyle(color: Colors.white24),
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
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
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
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
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
                  const Text('Sources to cache:',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 12)),
                  ...MapSource.all.map((source) {
                    final canDownload = source.supportsOfflineDownload;
                    return CheckboxListTile(
                      dense: true,
                      value: canDownload &&
                          selectedSourceIds.contains(source.id),
                      onChanged: canDownload
                          ? (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedSourceIds.add(source.id);
                                } else if (selectedSourceIds.length > 1) {
                                  selectedSourceIds.remove(source.id);
                                }
                              });
                            }
                          : null,
                      title: Text(
                        canDownload
                            ? source.name
                            : '${source.name} (no offline)',
                        style: TextStyle(
                          color:
                              canDownload ? Colors.white70 : Colors.white30,
                          fontSize: 13,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFF4A90D9),
                    );
                  }),
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
                        Text('~$totalTiles tiles',
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
                  if (totalTiles > 10000)
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
                    sourceIds: selectedSourceIds,
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
    required Set<String> sourceIds,
  }) async {
    // Start foreground service so download survives screen-off / app switch
    await DownloadForegroundService.start();

    final allSources = sourceIds.map((id) => MapSource.byId(id)).toList();
    // Split: base map sources use MapLibre native, WMS uses our downloader
    final baseSources =
        allSources.where((s) => s.type != MapSourceType.wms).toList();
    final wmsSources =
        allSources.where((s) => s.type == MapSourceType.wms).toList();

    // Create a combined progress stream for base maps + WMS
    final controller = StreamController<DownloadProgress>();
    final totalPhases = (baseSources.isNotEmpty ? 1 : 0) + wmsSources.length;
    int completedPhases = 0;

    Future<void> runDownloads() async {
      // Phase 1: Base map tiles via MapLibre native API
      if (baseSources.isNotEmpty) {
        final baseStream = offlineManager.downloadRegionMultiSource(
          regionName: name,
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
          sources: baseSources,
        );
        await for (final p in baseStream) {
          if (controller.isClosed) return;
          final scaled = (completedPhases + p.progressPercent) / totalPhases;
          if (p.isComplete && p.error == null) {
            completedPhases++;
          }
          controller.add(DownloadProgress(
            progressPercent: scaled,
            isComplete: false,
            error: p.error,
          ));
        }
      }

      // Phase 2+: WMS tiles via our own downloader
      for (final wms in wmsSources) {
        if (controller.isClosed) return;
        final wmsStream = offlineManager.downloadWmsRegion(
          wmsSource: wms,
          regionName: '$name (${wms.name})',
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
        );
        await for (final p in wmsStream) {
          if (controller.isClosed) return;
          final scaled = (completedPhases + p.progressPercent) / totalPhases;
          if (p.isComplete && p.error == null) {
            completedPhases++;
          }
          controller.add(DownloadProgress(
            progressPercent: scaled,
            isComplete: false,
            error: p.error,
          ));
        }
      }

      if (!controller.isClosed) {
        controller.add(const DownloadProgress(
          progressPercent: 1.0,
          isComplete: true,
        ));
        controller.close();
      }
    }

    runDownloads();

    final broadcastStream = controller.stream.asBroadcastStream();

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
    // Refresh region boundaries if they're visible
    if (_showRegionBoundaries) {
      _loadRegionBoundaries();
    }
  }

  Future<void> _toggleRegionBoundaries() async {
    if (_showRegionBoundaries) {
      // Hide
      await _mapProvider.removeAllRegionBoundaries();
      setState(() => _showRegionBoundaries = false);
    } else {
      // Show
      await _loadRegionBoundaries();
      setState(() => _showRegionBoundaries = true);
    }
  }

  Future<void> _loadRegionBoundaries() async {
    await _mapProvider.removeAllRegionBoundaries();
    final regions = await offlineManager.listRegions();
    for (final region in regions) {
      if (!region.matchesSource(_currentMapSource)) continue;
      await _mapProvider.addRegionBoundary(
        region.id.toString(),
        region.bounds.minLat,
        region.bounds.minLon,
        region.bounds.maxLat,
        region.bounds.maxLon,
        region.name,
      );
    }
  }

  Future<void> _openRegionsScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OfflineRegionsScreen()),
    );
    // Refresh boundaries if visible (user may have deleted regions)
    if (_showRegionBoundaries) {
      _loadRegionBoundaries();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _locationSub?.cancel();
    _connectivitySub?.cancel();
    _downloadProgressSub?.cancel();
    _removeRectanglePreview();
    _locationService.dispose();
    _connectivityService.dispose();
    _mapProvider.dispose();
    WmsTileServer.stop();
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
            styleString: _wmsResolvedStyle ?? _currentMapSource.styleString,
            initialCameraPosition: _lastCameraPosition,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: _onCameraIdle,
            onMapClick: _onMapClick,
            onMapLongClick: _onMapLongClick,
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
                  icon: Icons.layers,
                  tooltip: 'Map layers & offline',
                  onPressed: _showLayersAndDownloadSheet,
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

          // ── Drawing mode indicator: top-center ───────────────
          if (_isDrawingRectangle)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90D9).withAlpha(230),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.crop_square, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _rectangleStart == null
                            ? 'Tap first corner'
                            : 'Tap second corner',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
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
