# Architecture

## Layer Diagram

```
+------------------------------------------------------+
|                     UI Layer                         |
|  MapScreen (main view, controls, overlays)           |
+------------------------------------------------------+
        |               |               |
        v               v               v
+----------------+ +----------------+ +----------------+
|  MapService    | | LocationService| | GpxService     |
|  (map provider | | (GPS, accuracy)| | (import/export |
|   abstraction) | |                | |  recording)    |
+----------------+ +----------------+ +----------------+
        |                                      |
        v                                      v
+----------------+                    +----------------+
| OfflineManager |                    | Route/Waypoint |
| (tile download |                    | Models         |
|  MBTiles cache)|                    | (SQLite store) |
+----------------+                    +----------------+
        |
        v
+------------------------------------------------------+
|                   Data Layer                         |
|  Mapbox Tiles | WMS Responses | Local MBTiles | GPS  |
+------------------------------------------------------+
```

## Key Abstractions

### MapProvider Interface

The `MapService` wraps the Mapbox SDK behind an interface. This allows:
- Testing without a real map
- Future migration to MapLibre when it supports mobile 3D terrain
- Clean separation between map rendering and business logic

```dart
// Conceptual interface (not final API)
abstract class MapProvider {
  Future<void> initialize(String accessToken);
  void setCenter(double lat, double lng, double zoom);
  void addGeoJsonLayer(String id, Map<String, dynamic> geojson);
  void removeLayer(String id);
  Future<void> downloadRegion(BoundingBox bbox, int minZoom, int maxZoom);
  void dispose();
}
```

In practice, the Mapbox Flutter SDK uses a widget-based approach (`MapWidget`), so the abstraction will be at the service/controller level rather than wrapping the widget itself.

### Offline-First Data Flow

```
User requests map area
  -> Check local MBTiles cache
    -> Cache hit: serve tile from SQLite
    -> Cache miss + online: fetch from Mapbox, store in cache, serve
    -> Cache miss + offline: show placeholder or cached lower zoom
```

For WMS layers (orthophotos):
```
User enables orthophoto layer
  -> For visible tiles:
    -> Check local WMS tile cache
    -> Cache miss + online: request WMS GetMap, convert to tile, cache
    -> Cache miss + offline: skip (show base map only)
```

### Tile Caching Strategy

**Format**: MBTiles (SQLite database with tiles stored as blobs)

**Why MBTiles**:
- Single file per region, easy to manage
- SQLite is reliable on mobile
- Standard format, compatible with QGIS and other tools
- Mapbox SDK has built-in offline support, but custom MBTiles gives us control over WMS caching

**Storage structure**:
```
app_data/
  tiles/
    base_map/          # Mapbox vector tiles (managed by SDK)
    orthophoto/        # Cached WMS raster tiles
      veneto_2024.mbtiles
      trentino_2024.mbtiles
    terrain/           # Terrain-RGB tiles for 3D
  routes/
    *.gpx              # Saved GPX files
  db/
    routes.sqlite      # Route metadata, stats
```

**Tile download strategies**:
1. **Manual region**: User draws rectangle on map, selects zoom range. Tiles within bbox downloaded.
2. **Route buffer**: Given a GPX track, compute a buffer (e.g., 2km), calculate tile indices for the buffered bbox at each zoom level, download.

Tile index math (standard slippy map):
- `x = floor((lon + 180) / 360 * 2^zoom)`
- `y = floor((1 - ln(tan(lat_rad) + sec(lat_rad)) / pi) / 2 * 2^zoom)`

This is implemented in `lib/utils/tile_calculator.dart`.

### GPS and Location

`LocationService` wraps the `geolocator` package:
- Continuous position stream for track recording
- Configurable accuracy (high for recording, balanced for display)
- Permission handling (request, check, explain)
- Accuracy indicator on map (circle radius = horizontal accuracy in meters)

### GPX Handling

`GpxService` handles:
- **Import**: Parse GPX files (tracks, routes, waypoints) using the `gpx` package
- **Export**: Generate GPX from recorded tracks
- **Recording**: Accumulate position fixes into a track, compute running stats

GPX is the interchange format. Internally, routes are stored in SQLite for fast queries and metadata.

## Dependencies

| Package | Purpose |
|---------|---------|
| `mapbox_maps_flutter` | Map rendering, vector tiles, 3D terrain |
| `geolocator` | GPS position stream |
| `gpx` | GPX file parsing and generation |
| `path_provider` | Access to app storage directories |
| `sqflite` | Local SQLite database for routes and metadata |
| `permission_handler` | Runtime permission requests |
| `http` | WMS requests |

## Threading / Async

Flutter is single-threaded (event loop). Heavy operations use:
- **Isolates** for GPX parsing of large files
- **Async/await** for network requests and database queries
- The Mapbox SDK handles its own rendering thread

## Error Handling

- Network errors: catch, log, fall back to cached data
- GPS errors: show last known position, indicate staleness
- File errors: validate GPX before import, show clear error messages
- Tile download failures: retry with backoff, skip individual tiles, report progress
