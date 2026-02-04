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

  /// Style URL — OpenFreeMap bright style (free, no API key).
  static const defaultStyleUrl =
      'https://tiles.openfreemap.org/styles/bright';

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

    // Build a GeoJSON LineString from coordinate pairs [lat, lon]
    final geojson = {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        // GeoJSON uses [lon, lat] order
        'coordinates':
            coordinates.map((p) => [p[1], p[0]]).toList(),
      },
      'properties': <String, dynamic>{},
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
    await c.removeLayer('${id}_line');
    await c.removeSource(id);
  }

  @override
  Future<void> updateLocationMarker({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  }) async {
    final c = _controller;
    if (c == null) return;

    final pos = LatLng(latitude, longitude);

    // Remove previous circles
    if (_accuracyCircle != null) {
      await c.removeCircle(_accuracyCircle!);
    }
    if (_locationCircle != null) {
      await c.removeCircle(_locationCircle!);
    }

    // Accuracy circle (drawn first so it's behind the dot)
    _accuracyCircle = await c.addCircle(
      CircleOptions(
        geometry: pos,
        circleRadius: accuracyMeters,
        circleColor: '#4A90D9',
        circleOpacity: 0.15,
        circleStrokeColor: '#4A90D9',
        circleStrokeWidth: 1,
        circleStrokeOpacity: 0.3,
      ),
    );

    // Center dot
    _locationCircle = await c.addCircle(
      CircleOptions(
        geometry: pos,
        circleRadius: 8,
        circleColor: '#4A90D9',
        circleOpacity: 0.9,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
        circleStrokeOpacity: 1,
      ),
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
  }
}
