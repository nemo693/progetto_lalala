import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'package:maplibre_gl/maplibre_gl.dart';

/// Abstract interface for map operations.
///
/// The UI layer depends on this interface, not on MapLibre directly.
/// Phase 5 adds a MapboxProvider for 3D terrain; the rest of the app
/// stays unchanged.
abstract class MapProvider {
  /// Move the camera to the given position.
  Future<void> setCamera({
    required double latitude,
    required double longitude,
    required double zoom,
    double bearing = 0,
    double pitch = 0,
    bool animate = true,
  });

  /// Add a polyline layer from a list of [lat, lon] coordinate pairs.
  Future<void> addTrackLayer(String id, List<List<double>> coordinates);

  /// Remove a previously added layer.
  Future<void> removeLayer(String id);

  /// Add waypoint markers to the map.
  Future<void> addWaypointMarkers(
      String id, List<Map<String, dynamic>> waypoints);

  /// Remove waypoint markers.
  Future<void> removeWaypointMarkers(String id);

  /// Add or update the user location circle (accuracy indicator).
  Future<void> updateLocationMarker({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  });

  /// Reset bearing to north.
  Future<void> resetNorth();

  /// Clean up resources.
  void dispose();
}

/// MapLibre-backed implementation of [MapProvider].
///
/// Operates on the [MapLibreMapController] exposed by the MapLibreMap widget's
/// onMapCreated callback. The widget itself lives in MapScreen — this class
/// handles the controller-level operations.
class MapLibreProvider implements MapProvider {
  MapLibreMapController? _controller;
  Circle? _locationCircle;
  Circle? _accuracyCircle;

  // Stored state for recalculating accuracy circle on zoom changes
  double? _lastAccuracyMeters;
  double? _lastLat;

  /// Convert a distance in meters to screen pixels at the given zoom and
  /// latitude.  MapLibre CircleOptions.circleRadius is in screen pixels,
  /// so we must do this conversion ourselves.
  ///
  /// Ground resolution formula:
  ///   metersPerPixel = 156543.03392 × cos(lat × π / 180) / 2^zoom
  static double metersToPixels(double meters, double zoom, double latitude) {
    final metersPerPixel =
        156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);
    final px = meters / metersPerPixel;
    // Clamp to a reasonable range: at least 4px so it's visible, at most 500px
    return px.clamp(4.0, 500.0);
  }

  /// Style URLs — OpenFreeMap bright is the primary; MapLibre demo tiles as
  /// fallback in case OpenFreeMap is temporarily down.
  static const defaultStyleUrl =
      'https://tiles.openfreemap.org/styles/bright';

  /// Fallback style URL (MapLibre demo tiles — low-res but always available).
  static const fallbackStyleUrl =
      'https://demotiles.maplibre.org/style.json';

  /// Bind to the controller after map creation.
  void attach(MapLibreMapController controller) {
    _controller = controller;
  }

  MapLibreMapController? get controller => _controller;

  @override
  Future<void> setCamera({
    required double latitude,
    required double longitude,
    required double zoom,
    double bearing = 0,
    double pitch = 0,
    bool animate = true,
  }) async {
    final c = _controller;
    if (c == null) return;

    final update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(latitude, longitude),
        zoom: zoom,
        bearing: bearing,
        tilt: pitch,
      ),
    );

    if (animate) {
      await c.animateCamera(update);
    } else {
      await c.moveCamera(update);
    }
  }

  @override
  Future<void> addTrackLayer(
      String id, List<List<double>> coordinates) async {
    final c = _controller;
    if (c == null) return;

    // Remove any existing layer/source with this id to avoid duplicate crashes
    await removeLayer(id);

    // Build a GeoJSON FeatureCollection with a LineString from coordinate pairs [lat, lon].
    // MapLibre's native GeoJSON source expects a FeatureCollection, not a bare Feature.
    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            // GeoJSON uses [lon, lat] order
            'coordinates':
                coordinates.map((p) => [p[1], p[0]]).toList(),
          },
          'properties': <String, dynamic>{},
        },
      ],
    };

    await c.addSource(id, GeojsonSourceProperties(data: geojson));
    await c.addLineLayer(
      id,
      '${id}_line',
      const LineLayerProperties(
        lineColor: '#FF4444',
        lineWidth: 3.0,
        lineOpacity: 0.85,
      ),
    );
  }

  @override
  Future<void> removeLayer(String id) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.removeLayer('${id}_line');
    } catch (_) {
      // Layer may not exist — ignore
    }
    try {
      await c.removeSource(id);
    } catch (_) {
      // Source may not exist — ignore
    }
  }

  // Track symbols added for waypoint markers
  final Map<String, List<Symbol>> _waypointSymbols = {};

  @override
  Future<void> addWaypointMarkers(
      String id, List<Map<String, dynamic>> waypoints) async {
    final c = _controller;
    if (c == null) return;

    // Remove existing markers for this id
    await removeWaypointMarkers(id);

    final symbols = <Symbol>[];
    for (final wpt in waypoints) {
      final lat = wpt['lat'] as double;
      final lon = wpt['lon'] as double;
      final name = wpt['name'] as String? ?? '';

      final symbol = await c.addSymbol(
        SymbolOptions(
          geometry: LatLng(lat, lon),
          textField: name,
          textSize: 12,
          textColor: '#FFFFFF',
          textHaloColor: '#000000',
          textHaloWidth: 1,
          textOffset: const Offset(0, 1.5),
          iconImage: 'marker-15', // MapLibre default marker icon
          iconSize: 1.5,
        ),
      );
      symbols.add(symbol);
    }
    _waypointSymbols[id] = symbols;
  }

  @override
  Future<void> removeWaypointMarkers(String id) async {
    final c = _controller;
    if (c == null) return;

    final symbols = _waypointSymbols.remove(id);
    if (symbols != null) {
      for (final s in symbols) {
        try {
          await c.removeSymbol(s);
        } catch (_) {
          // Symbol may already be removed — ignore
        }
      }
    }
  }

  @override
  Future<void> updateLocationMarker({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  }) async {
    final c = _controller;
    if (c == null) return;

    // Store for recalculation on zoom changes
    _lastLat = latitude;
    _lastAccuracyMeters = accuracyMeters;

    final zoom = c.cameraPosition?.zoom ?? 15;
    final radiusPx = metersToPixels(accuracyMeters, zoom, latitude);

    final pos = LatLng(latitude, longitude);

    // Remove previous circles (catch errors from stale references after style reload)
    if (_accuracyCircle != null) {
      try {
        await c.removeCircle(_accuracyCircle!);
      } catch (_) {
        // Circle may have been invalidated by style reload
      }
      _accuracyCircle = null;
    }
    if (_locationCircle != null) {
      try {
        await c.removeCircle(_locationCircle!);
      } catch (_) {
        // Circle may have been invalidated by style reload
      }
      _locationCircle = null;
    }

    // Accuracy circle (drawn first so it's behind the dot)
    // Make it more visible with stronger colors and larger minimum size
    _accuracyCircle = await c.addCircle(
      CircleOptions(
        geometry: pos,
        circleRadius: radiusPx.clamp(8.0, 500.0), // Minimum 8px for visibility
        circleColor: '#4A90D9',
        circleOpacity: 0.2, // Increased from 0.15
        circleStrokeColor: '#4A90D9',
        circleStrokeWidth: 2, // Increased from 1
        circleStrokeOpacity: 0.5, // Increased from 0.3
      ),
    );

    // Center dot (fixed 10px, slightly larger for better visibility)
    _locationCircle = await c.addCircle(
      CircleOptions(
        geometry: pos,
        circleRadius: 10, // Increased from 8
        circleColor: '#4A90D9',
        circleOpacity: 1.0, // Fully opaque
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3, // Increased from 2
        circleStrokeOpacity: 1,
      ),
    );
  }

  /// Clear stale circle references after a style reload.
  /// The circles no longer exist on the map after a reload, so we just
  /// null the references to prevent removeCircle from failing silently
  /// while leaving ghost circles behind.
  void clearLocationMarkerRefs() {
    _locationCircle = null;
    _accuracyCircle = null;
  }

  /// Recalculate the accuracy circle size for the current zoom level.
  /// Call this from the map's onCameraIdle callback.
  Future<void> onCameraIdle() async {
    final c = _controller;
    if (c == null || _accuracyCircle == null) return;
    final lat = _lastLat;
    final meters = _lastAccuracyMeters;
    if (lat == null || meters == null) return;

    final zoom = c.cameraPosition?.zoom ?? 15;
    final radiusPx = metersToPixels(meters, zoom, lat).clamp(8.0, 500.0);

    await c.updateCircle(
      _accuracyCircle!,
      CircleOptions(circleRadius: radiusPx),
    );
  }

  @override
  Future<void> resetNorth() async {
    final c = _controller;
    if (c == null) return;
    await c.animateCamera(CameraUpdate.bearingTo(0));
  }

  @override
  void dispose() {
    _controller = null;
    _locationCircle = null;
    _accuracyCircle = null;
    _lastAccuracyMeters = null;
    _lastLat = null;
    _waypointSymbols.clear();
  }
}
