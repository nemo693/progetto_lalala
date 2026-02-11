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
|  OpenFreeMap Tiles | WMS Responses | Local MBTiles | GPS |
+------------------------------------------------------+
```

## Key Abstractions

### MapProvider Interface

The `MapService` wraps the map SDK behind a `MapProvider` interface. This allows:
- Testing without a real map
- Swapping MapLibre (2D, Phases 1–4) for Mapbox (3D, Phase 5) without rewriting the app
- Clean separation between map rendering and business logic

The active implementation is `MapLibreProvider` which wraps MapLibre GL.

```dart
abstract class MapProvider {
  Future<void> setCamera({...});
  Future<void> addTrackLayer(String id, List<List<double>> coordinates);
  Future<void> removeLayer(String id);
  Future<void> updateLocationMarker({...});
  Future<void> resetNorth();
  void dispose();
}
```

The MapLibre Flutter SDK uses a widget-based approach (`MapLibreMap`). The `MapLibreProvider` operates on the `MapLibreMapController` exposed via the widget's `onMapCreated` callback.

### Offline-First Data Flow

```
User requests map area
  -> Check local MBTiles cache
    -> Cache hit: serve tile from SQLite
    -> Cache miss + online: fetch from tile server, store in cache, serve
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

**Implementation**: MapLibre Native Offline API (Phase 3, implemented Feb 2026)

**How it works**:
- MapLibre GL Native has a built-in offline region API
- `downloadOfflineRegion()` downloads tiles for a bounding box and zoom range
- Tiles stored in MapLibre's internal SQLite cache (not MBTiles format, but similar)
- Cached tiles served automatically when offline — no app code needed
- `OfflineManager` wraps MapLibre's API with progress tracking and foreground service

**Why MapLibre Native API** (vs custom MBTiles):
- Zero-config: tiles served automatically from cache when offline
- Native implementation: faster and more reliable than Dart-side SQLite
- Progress callbacks: built-in download progress and completion events
- Region management: list, delete, and query offline regions via SDK
- Future-proof: MapLibre team maintains caching logic, handles format changes

**Storage structure** (managed by MapLibre, not directly accessed by app):
```
app_data/
  cache/
    mbgl-offline.db    # MapLibre's native tile cache (SQLite)
    mbgl-cache.db      # Runtime tile cache (separate from offline regions)
  app_flutter/
    routes/
      *.gpx            # Saved GPX files
    db/
      routes.db        # Route metadata (RouteStorageService)
```

**Tile download strategies** (implemented in `OfflineManager`):
1. **Manual region** (`downloadRegion()`): User selects visible map area, configures zoom range (6–16), downloads all tiles in bbox
2. **Route buffer** (`downloadRouteRegion()`): Given a GPX track, compute a 2km buffer corridor, download tiles for buffered bbox
3. **Background download**: Android foreground service (`DownloadForegroundService`) keeps download alive when screen is off

**Tile index math** (standard slippy map, implemented in `lib/utils/tile_calculator.dart`):
- `x = floor((lon + 180) / 360 * 2^zoom)`
- `y = floor((1 - ln(tan(lat_rad) + sec(lat_rad)) / pi) / 2 * 2^zoom)`

**Concurrency control** (fixed in commit `35d5539`):
- MapLibre's `downloadOfflineRegion()` had a deadlock bug when downloading WMS tiles
- Bug: broken semaphore implementation caused download to hang indefinitely
- Fix: replaced semaphore logic with queue-based concurrency control
- Now downloads complete reliably, even for large regions

**Future (Phase 4 WMS caching)**:
- WMS tiles (orthophotos) will also use MapLibre's offline region API
- Alternative: custom MBTiles for WMS responses, then add as RasterSource
- Decision pending based on WMS endpoint testing (see `docs/TODO.md`)

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

| Package | Purpose | Phase |
|---------|---------|-------|
| `maplibre_gl` | Map rendering, vector tiles, offline regions | 1, 3 |
| `geolocator` | GPS position stream | 1, 2 |
| `gpx` | GPX file parsing and generation | 2 |
| `path_provider` | Access to app storage directories | 2, 3 |
| `file_picker` | GPX file import UI | 2 |
| `permission_handler` | Runtime permission requests | 1, 2, 3 |
| `connectivity_plus` | Network status detection (online/offline) | 3 |
| `flutter_foreground_task` | Android foreground service for background downloads | 3 |
| `http` | WMS requests (Phase 4, not yet used) | 4 |

## Threading / Async

Flutter is single-threaded (event loop). Heavy operations use:
- **Isolates** for GPX parsing of large files
- **Async/await** for network requests and database queries
- The MapLibre SDK handles its own rendering thread

## Error Handling

- Network errors: catch, log, fall back to cached data
- GPS errors: show last known position, indicate staleness
- File errors: validate GPX before import, show clear error messages
- Tile download failures: retry with backoff, skip individual tiles, report progress
