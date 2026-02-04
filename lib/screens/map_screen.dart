import 'dart:async';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../services/map_service.dart';
import '../services/location_service.dart';

/// Main screen — map fills the screen with minimal overlay controls.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapProvider = MapLibreProvider();
  final _locationService = LocationService();

  StreamSubscription<Position>? _locationSub;
  Position? _currentPosition;
  String? _locationError;
  bool _styleLoaded = false;
  bool _followingUser = true;

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
    // Draw location marker now that the style is ready
    final pos = _currentPosition;
    if (pos != null) {
      _updateLocationMarker(pos);
    }
  }

  void _onCameraIdle() {
    // Recalculate accuracy circle size for new zoom level
    _mapProvider.onCameraIdle();
  }

  void _zoomToLocation() async {
    setState(() => _followingUser = true);
    final pos = _currentPosition;
    if (pos != null) {
      _moveCameraToPosition(pos);
    } else {
      // Try a fresh fix
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

  @override
  void dispose() {
    _locationSub?.cancel();
    _locationService.dispose();
    _mapProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            tiltGesturesEnabled: false, // No 3D tilt in 2D mode
            compassEnabled: false, // We draw our own
            myLocationEnabled: false, // We draw our own location marker
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
              ],
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
    // Large touch target (48x48) for glove use
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
