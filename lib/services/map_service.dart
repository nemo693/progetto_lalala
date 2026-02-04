// TODO(phase1): Implement MapService as an abstraction over the Mapbox SDK
//
// This service wraps map operations to allow future migration from Mapbox
// to MapLibre. The UI layer should call MapService methods rather than
// interacting with the Mapbox SDK directly.
//
// Key responsibilities:
// - Initialize the map with access token and default style
// - Set camera position (center, zoom, bearing, pitch)
// - Add/remove GeoJSON layers (for GPX tracks, waypoints)
// - Manage layer visibility (base map, orthophoto, hybrid)
// - Handle map events (tap, long press, camera move)
//
// Note: The Mapbox Flutter SDK uses a widget (MapWidget) that manages its
// own rendering. This service operates on the MapboxMap controller that
// the widget exposes via its onMapCreated callback, rather than wrapping
// the widget itself.

/// Abstract interface for map operations.
/// Concrete implementation will use Mapbox; can be swapped for MapLibre later.
abstract class MapProvider {
  Future<void> initialize();
  void setCamera({
    required double latitude,
    required double longitude,
    required double zoom,
    double bearing = 0,
    double pitch = 0,
  });
  void addTrackLayer(String id, List<List<double>> coordinates);
  void removeLayer(String id);
  void dispose();
}

// TODO(phase1): class MapboxMapProvider implements MapProvider { ... }
