# Changelog

All notable changes to AlpineNav will be documented in this file.

## [Unreleased]

### Phase 3 - Offline Maps (Code Complete, Device Testing Pending)

#### Added (2026-02-11)
- **Offline region downloads**: Download map tiles for visible area or buffered route corridor
- **Region management UI**: List, delete, and clear all offline regions (`offline_regions_screen.dart`)
- **Download progress overlay**: Real-time progress bar with percentage and cancel button
- **Foreground service**: Android foreground service keeps downloads alive when screen is off (`download_foreground_service.dart`)
- **Offline indicator**: Orange "Offline" badge appears when network is unavailable
- **Connectivity detection**: Auto-detect network status via `connectivity_plus`
- **Tile estimation**: Pre-download tile count and size estimates to prevent storage surprises
- **MapLibre native offline API**: Refactored `OfflineManager` to use MapLibre's built-in offline region API

#### Fixed (2026-02-10)
- **WMS download deadlock** (commit `35d5539`): MapLibre's `downloadOfflineRegion()` had a semaphore deadlock bug. Replaced broken semaphore with queue-based concurrency control. Downloads now complete reliably.
- **WMS tile loading** (commit `179adfa`): Switched WMS version from 1.3.0 to 1.1.0 to fix tile rendering issues with Italian regional endpoints.

#### Changed
- **Offline tiles**: Now stored in MapLibre's native cache (SQLite) instead of custom MBTiles. Tiles served automatically when offline with zero app code.
- **Download UI**: Bottom sheet with three options: "Download visible area", "Download around route", "Manage offline regions"

---

## Phase 2 - Routes (Complete, Field-Tested)

### Added (2026-02-05 to 2026-02-09)
- **GPX import**: Load GPX files from device storage with file picker
- **GPX parsing**: Parse tracks, waypoints, and metadata using `gpx` package
- **Track display**: Render GPX tracks as orange polylines on map
- **Waypoint markers**: Display waypoints with name labels
- **Track recording**: Start/stop/pause GPS track recording
- **Live stats**: Distance, elapsed time, current elevation, elevation gain during recording
- **Route persistence**: Save and load routes from local storage (`RouteStorageService`)
- **Route list**: Manage saved routes (view, delete, load)
- **Interactive rectangle drawing**: Draw download regions on map for offline area selection

### Fixed (2026-02-09) - Device Testing on Redmi 14

#### Accuracy Circle Visibility
- **Issue**: GPS accuracy circle barely visible (too small, too transparent)
- **Fix**: Increased opacity (0.15 → 0.2), stroke width (1px → 2px), stroke opacity (0.3 → 0.5), minimum radius (4px → 8px). Center dot larger (8px → 10px) and fully opaque.

#### Auto-Follow Mode
- **Issue**: No visual indicator for auto-follow state, can't disable once enabled
- **Fix**: Location button highlights blue when auto-follow active. Tooltip changes to "Following location". Auto-follow disables when user manually pans >100m from position.

#### GPX Import Crashes
- **Issue**: No error handling for permissions, invalid files, or empty tracks
- **Fix**: Comprehensive error handling with specific messages for permissions, file access, and format issues. File picker filters to `.gpx` and `.xml` only. Validates empty track data. Errors display for 6 seconds.

#### Save Recording Crashes
- **Issue**: No validation, no error handling, GPS mode not restored on failure
- **Fix**: Try-catch with validation (minimum 2 points), specific error messages for permissions/storage issues, guaranteed GPS mode restoration in `finally` block. Mounted state checks before `setState`.

### Fixed (2026-02-07) - Build Issues

#### GeoJSON FeatureCollection Crash
- **Issue**: `addTrackLayer` passed bare GeoJSON `Feature` to MapLibre's `addSource()`, but native code expects `FeatureCollection`. Caused JNI abort crash.
- **Fix**: Wrapped all GeoJSON Features in FeatureCollections.

#### Duplicate Layer Crash
- **Issue**: Opening second GPX track while one already displayed crashed (duplicate layer ID).
- **Fix**: Call `removeLayer(id)` at start of `addTrackLayer` to clean up before adding. Wrapped all `removeLayer`, `removeSource`, `removeSymbol` calls in try/catch.

---

## Phase 1 - Foundation (Complete, Field-Tested)

### Added (2026-02-01 to 2026-02-04)
- **MapLibre GL integration**: Full-screen map with OpenFreeMap bright tiles
- **GPS location**: Blue dot with zoom-dependent accuracy circle
- **Location tracking**: Auto-follow mode with visual indicator
- **Map controls**: Zoom, pan, rotate, reset north
- **Coordinate display**: Live GPS position and altitude in overlay chip
- **Permission handling**: Runtime location permission flow with clear error messages
- **Error banner**: Red banner for permission denials or GPS errors

### Fixed (2026-02-03)

#### Accuracy Circle Pixels vs Meters
- **Issue**: `CircleOptions.circleRadius` received meters instead of pixels. Circle size wrong at all zoom levels.
- **Fix**: Added `metersToPixels()` static method with ground-resolution formula. Accuracy circle now recalculates on zoom via `onCameraIdle()`.

#### Missing Imports
- **Issue**: `Point` class needed explicit import from `dart:math` in `map_screen.dart`.
- **Fix**: Added `import 'dart:math'` to `map_screen.dart`.

#### Test File
- **Issue**: Default `widget_test.dart` referenced non-existent `MyApp` class.
- **Fix**: Replaced with `AlpineNavApp` smoke test (app creates without error).

#### Tile Source Fallback
- **Issue**: No fallback if OpenFreeMap tile server is down.
- **Fix**: Added `MapLibreProvider.fallbackStyleUrl` pointing to `demotiles.maplibre.org/style.json`.

### Fixed (2026-02-02) - Windows Build Issues

#### `objective_c` Build Hook Crash
- **Issue**: Native asset build hook for `objective_c` (transitive dep via `path_provider` → `path_provider_foundation`) can't handle spaces in paths (e.g., `C:\Users\Emilio Dorigatti`).
- **Fix**: Added `dependency_overrides` in `pubspec.yaml` to pin `path_provider_foundation: 2.4.0` (pre-FFI version without `objective_c` dependency). Safe because `path_provider_foundation` is iOS/macOS only.

#### `update_engine_version.ps1` Failure
- **Issue**: PowerShell `Set-Content` fails to write `engine.stamp` on first run after cache clear or Flutter upgrade (spaces in Flutter SDK path).
- **Workaround**: Run `flutter run` twice (first fails, second succeeds).
- **Permanent fix**: Move Flutter SDK to `C:\flutter` (not yet done).

---

## Development Milestones

- **2026-02-11**: Phase 3 code complete (offline maps). Device testing pending.
- **2026-02-09**: Phase 2 device testing complete on Redmi 14. All critical bugs fixed.
- **2026-02-04**: Phase 1 field-tested and stable. Proceeding to Phase 2.
- **2026-02-01**: Project initialized. Flutter app scaffold created.

---

## Testing Status

| Phase | Code Complete | Device Tested | Field Tested | Status |
|-------|---------------|---------------|--------------|--------|
| Phase 1 | ✅ | ✅ | ✅ | **Complete** |
| Phase 2 | ✅ | ✅ | ✅ | **Complete** (except export) |
| Phase 3 | ✅ | ⏳ | ⏳ | **Testing pending** |
| Phase 4 | ❌ | ❌ | ❌ | Research phase |
| Phase 5 | ❌ | ❌ | ❌ | Deferred to 2026 H2 |

---

## Known Issues

### Windows Development (Non-Critical)
- **Flutter SDK path with spaces**: Causes `update_engine_version.ps1` to fail on first run. Workaround: run twice. Permanent fix: move SDK to `C:\flutter`.
- **`objective_c` dependency**: Fixed via `dependency_overrides` (pins pre-FFI version of `path_provider_foundation`).

### MapLibre SDK (Resolved)
- **WMS download deadlock**: Fixed in commit `35d5539` (replaced broken semaphore with queue-based concurrency).
- **GeoJSON format**: Fixed (wrap all Features in FeatureCollections).
- **Duplicate layers**: Fixed (remove before add, try/catch on all layer operations).

### Phase 2 Incomplete
- **Export routes**: Not yet implemented. Low priority (import and recording work fine).

---

## Future Work

See `docs/TODO.md` for detailed TODO list, open questions, and testing checklist.

### Immediate Priorities
1. Device test Phase 3 (offline downloads) on Redmi 14
2. Fix any issues found in testing
3. Update docs to mark Phase 3 complete
4. Research WMS endpoints for Phase 4

### Phase 4 Planning
- Survey Italian regional WMS endpoints (see `docs/DATA_SOURCES.md`)
- Decide on WMS caching strategy (MapLibre native vs custom MBTiles)
- Design layer switching UI (base map / orthophoto / hybrid)
- Benchmark WMS tile download performance

### Phase 5 Planning
- Wait for MapLibre 3D terrain support (expected late 2026)
- If not available, evaluate Mapbox Maps SDK
- Research custom DTM integration (Italian high-res terrain data)
- Test 3D rendering performance on Redmi 14

---

## Version History

AlpineNav does not use semantic versioning yet (pre-release, internal development only). Once Phase 4 is complete and field-tested, versioning will begin at `0.1.0`.

**Current build**: Debug APK, commit `db9c8ce` (2026-02-11)
