# AlpineNav - Claude Code Context

## Project Summary

AlpineNav is an offline-first outdoor navigation app for skitouring, hiking, and climbing. Primary focus on the Italian Alps. Built with Flutter + MapLibre GL (2D) with Mapbox reserved for 3D terrain in Phase 5.

**Philosophy**: Minimal, functional UI. No animations, no unnecessary features. Map fills the screen. Information density over whitespace. Inspired by ViewRanger's original simplicity.

## Tech Stack

- **Framework**: Flutter (Dart)
- **Mapping (2D)**: MapLibre GL for Flutter (`maplibre_gl`) + OpenFreeMap tiles
- **Mapping (3D, Phase 5)**: Mapbox Maps SDK (deferred until 3D terrain needed)
- **Platform**: Android first (no iOS until Android is solid)
- **Offline tiles**: MapLibre native offline API (automatic tile cache)
- **Background downloads**: `flutter_foreground_task` (Android foreground service)
- **Connectivity**: `connectivity_plus` for online/offline detection
- **State management**: TBD (start simple, add if needed)

## Developer Context

The developer is experienced with:
- R, PostgreSQL, QGIS, GIS/remote sensing, geospatial data processing
- Python, bash, Linux
- Coordinate systems, projections, WMS/WMTS, DTM, tiles, raster processing

The developer is **new to**:
- Dart, Flutter, mobile development, MapLibre/Mapbox SDK
- Explain Flutter/Dart concepts, widget lifecycle, build patterns
- Do NOT explain GIS concepts (tiles, projections, WMS, DTM, coordinate systems)

## Feature Roadmap

### Phase 1 - Foundation
- Display base map (MapLibre + OpenFreeMap)
- GPS location with accuracy indicator
- Basic map controls (zoom, pan, compass)

### Phase 2 - Routes
- Import GPX files (tracks + waypoints)
- Display routes on map
- Record GPX tracks with stats (distance, elevation, time, pace)
- Manage saved routes (list, delete, export)

### Phase 3 - Offline
- Download offline map regions (rectangle selection)
- Download tiles around a route (buffered)
- Storage management
- Offline indicator and graceful degradation

### Phase 4 - WMS Data
- Italian regional orthophotos via WMS
- Cache WMS responses as tiles for offline use
- Layer switching (base map / orthophoto / hybrid)

### Phase 5 - 3D Terrain (Mapbox)
- Add Mapbox SDK alongside MapLibre for 3D terrain only
- Mapbox terrain-RGB visualization
- Custom DTM integration (Italian high-res)
- Drape orthophotos over 3D terrain
- Terrain exaggeration control

### Not in scope
- Turn-by-turn navigation, social features, weather, iOS (for now)

## Key Commands

**IMPORTANT**: `flutter` is NOT on PATH in Claude Code sessions. Always use the full path with `.bat` extension and quote it. The working directory must be set with `cd` first because the path has spaces.

```bash
# The flutter command in Claude Code (spaces in path require cd + quoted .bat):
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" <command>

# Examples:
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" analyze
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" run
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" build apk
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" pub get
```

Why this is needed:
- Flutter SDK lives at `C:\Users\Emilio Dorigatti\flutter` (space in username)
- Bare `flutter` fails: not on PATH in the Claude Code bash shell
- Unquoted full path fails: shell splits on the space ("C:\Users\Emilio" not recognized)
- Must use `.bat` extension explicitly on Windows

## Architecture Decisions

1. **MapLibre for 2D, Mapbox for 3D only**: MapLibre is open source, no API keys needed. Mapbox is deferred to Phase 5 for 3D terrain. If MapLibre ships mobile 3D terrain (expected late 2026), Mapbox may not be needed at all.
2. **Abstract the map layer**: `MapProvider` interface in `map_service.dart` allows swapping between MapLibre and Mapbox without touching the rest of the app. `MapLibreProvider` is the active implementation.
3. **Offline-first**: All features must work without network. Tile cache uses MapLibre's native offline API (`downloadOfflineRegion`). Route data stored locally as GPX files. Background downloads use Android foreground service to survive screen-off.
4. **Android-only**: Simpler setup, cheaper ($25 vs $99/year), no Mac needed.
5. **Minimal UI**: Map fills screen. Controls overlay minimally. No bottom nav bars, no card designs, no Material floating aesthetic. Muted colors, large touch targets (gloves).

## File Structure

```
lib/
  main.dart                              # App entry point, OfflineManager init
  screens/
    map_screen.dart                      # Main map view (primary screen)
    routes_screen.dart                   # Route list management
    offline_regions_screen.dart          # Offline region management
  services/
    map_service.dart                     # Map provider abstraction
    location_service.dart                # GPS location handling
    offline_manager.dart                 # Offline tile management (MapLibre native API)
    gpx_service.dart                     # GPX import/export/recording
    route_storage_service.dart           # Route persistence (GPX files + JSON metadata)
    connectivity_service.dart            # Network status detection
    download_foreground_service.dart     # Android foreground service for downloads
  widgets/
    download_progress_overlay.dart       # Download progress UI overlay
  models/
    route.dart                           # Route/track data model
    waypoint.dart                        # Waypoint data model
  utils/
    tile_calculator.dart                 # Tile math (bbox to tile indices, etc.)
scripts/
  setup_env.sh                           # Cloud environment setup
  gradle_proxy.py                        # Local proxy for Gradle in cloud environments
docs/
  ARCHITECTURE.md                        # Technical architecture
  DATA_SOURCES.md                        # Italian geoportal endpoints
  ROADMAP.md                             # Detailed feature roadmap
```

## Tile Source

Base map tiles come from **OpenFreeMap** (free, no API key, no quotas).
Style URL: `https://tiles.openfreemap.org/styles/bright`

This is configured in `MapLibreProvider.defaultStyleUrl` in `lib/services/map_service.dart`.

## Key Documentation Links

- MapLibre GL Flutter: https://pub.dev/packages/maplibre_gl
- MapLibre GL Native: https://github.com/maplibre/flutter-maplibre-gl
- OpenFreeMap: https://openfreemap.org/
- Flutter docs: https://docs.flutter.dev/
- Dart language: https://dart.dev/language
- GPX format spec: https://www.topografix.com/gpx.asp
- MBTiles spec: https://github.com/mapbox/mbtiles-spec
- Mapbox Maps SDK (Phase 5 only): https://pub.dev/packages/mapbox_maps_flutter

## Project Documentation

- `docs/ROADMAP.md`: Detailed feature roadmap with phase breakdown
- `docs/ARCHITECTURE.md`: Technical architecture and design decisions
- `docs/DATA_SOURCES.md`: Italian geoportal WMS endpoints
- `docs/TODO.md`: Current TODOs, open points, and testing checklist

## Secrets

No API keys are needed for Phases 1–4 (MapLibre + OpenFreeMap are fully open).

Mapbox tokens (Phase 5 only) go in:
- `android/app/src/main/res/values/mapbox_access_token.xml` (for native SDK init)
- `~/.gradle/gradle.properties` as `MAPBOX_DOWNLOADS_TOKEN=sk.xxx`

**NEVER commit secrets.** The `.gitignore` excludes token files.

## Current Status & Next Steps

### What's done (Phase 1 — analyze-clean, needs device test)
- `pubspec.yaml`: MapLibre GL (`maplibre_gl: ^0.25.0`) + geolocator, permission_handler, file_picker
- `lib/services/map_service.dart`: `MapProvider` interface + `MapLibreProvider` implementation (camera, track layers, location marker with zoom-dependent accuracy circle, reset north). Fallback style URL added (`demotiles.maplibre.org`).
- `lib/services/location_service.dart`: Full implementation (permission flow, one-shot position, streaming GPS, configurable accuracy)
- `lib/screens/map_screen.dart`: Full-screen MapLibre map with OpenFreeMap bright tiles, GPS blue dot with zoom-corrected accuracy circle, reset-north button, zoom-to-location button, coordinate/altitude chip, error banner for permission issues. Default camera on Dolomites (46.5, 11.35)
- `scripts/setup_env.sh`: Cloud env setup (Flutter install, Android SDK install, Gradle proxy, android scaffold, pub get — no tokens needed)
- `scripts/gradle_proxy.py`: Local forwarding proxy for Gradle in cloud environments (Java can't auth with container proxy)
- `android/app/src/main/AndroidManifest.xml`: Location permissions (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`) and `INTERNET` permission present
- `test/widget_test.dart`: Basic smoke test (app creates without error) — passes
- `flutter analyze`: **0 issues**
- `flutter test`: **All tests passed**

### Build-test status
- `flutter analyze` — clean (0 issues)
- `flutter test` — 55 tests passed
- `flutter build apk --debug` — **builds successfully** (181MB debug APK). Requires Android SDK setup (automated by `scripts/setup_env.sh`).
- `flutter run --release` — **builds successfully** (52.5MB release APK). Note: first run always fails with "Flusso illeggibile" (`Set-Content` error in `update_engine_version.ps1` due to spaces in Flutter SDK path) — re-run immediately and it works.

### Known Windows issues (spaces in user path)
The Flutter SDK is installed at `C:\Users\Emilio Dorigatti\flutter` — the space in the username causes two recurring issues:
1. **`update_engine_version.ps1` failure**: PowerShell `Set-Content` fails to write `engine.stamp` on first run after cache clear or Flutter upgrade. Workaround: run the command twice.
2. **`objective_c` build hook failure**: The native asset build hook for `objective_c` (transitive dep via `path_provider` → `path_provider_foundation`) can't handle spaces in paths. Fixed via `dependency_overrides` in `pubspec.yaml`. Moving the Flutter SDK to `C:\flutter` would permanently fix both issues.

### What's been fixed since initial code
1. **Accuracy circle**: `CircleOptions.circleRadius` was receiving meters instead of pixels. Added `metersToPixels()` static method with ground-resolution formula. Accuracy circle now recalculates on zoom via `onCameraIdle()`.
2. **Missing `dart:math` import**: `Point` class needed explicit import from `dart:math` in `map_screen.dart`.
3. **Test file**: Default `widget_test.dart` referenced non-existent `MyApp` — replaced with `AlpineNavApp` smoke test.
4. **Tile source fallback**: Added `MapLibreProvider.fallbackStyleUrl` pointing to `demotiles.maplibre.org/style.json`.
5. **Windows spaces-in-path build fix**: `objective_c` native build hook crashes on Windows when user profile path contains spaces (e.g. `C:\Users\Emilio Dorigatti`). Fixed by adding `dependency_overrides` in `pubspec.yaml` to pin `path_provider_foundation: 2.4.0` (pre-FFI version without `objective_c` dependency). Safe because `path_provider_foundation` is iOS/macOS only — never used on Android.
6. **GeoJSON FeatureCollection crash fix**: `addTrackLayer` was passing a bare GeoJSON `Feature` to MapLibre's `addSource()`, but the native code (`mbgl::android::geojson::FeatureCollection::convert`) expects a `FeatureCollection`. Wrapped the Feature in a FeatureCollection to fix a JNI abort crash when displaying GPX tracks.
7. **Duplicate layer crash fix**: Opening a second GPX track while one was already displayed crashed because `addTrackLayer` tried to add a source/layer with an ID that already existed. Fixed by: (a) calling `removeLayer(id)` at the start of `addTrackLayer` to clean up before adding, and (b) wrapping `removeLayer`, `removeSource`, and `removeSymbol` calls in try/catch so they don't crash if the layer/source/symbol doesn't exist.

### Device testing fixes (Redmi 14, Feb 2026)
**Issues found and fixed:**
1. **Accuracy circle not visible**: Increased opacity (0.15 → 0.2), stroke width (1px → 2px), stroke opacity (0.3 → 0.5), minimum radius (4px → 8px). Center dot larger (8px → 10px) and fully opaque. Circle now clearly visible at all zoom levels.
2. **Auto-follow has no visual indicator**: Location button now highlights in blue when auto-follow is active. Tooltip changes to "Following location" when enabled. Users can now see the mode at a glance.
3. **Auto-follow can't be disabled**: Added logic to disable auto-follow when user manually pans map >100m from their position. Button returns to gray state. Tap to re-enable.
4. **GPX import crashes**: Added comprehensive error handling with specific messages for permissions, file access, and format issues. File picker now filters to `.gpx` and `.xml` only. Validates empty track data. Errors display for 6 seconds.
5. **Save recording crashes**: Added try-catch with validation (minimum 2 points), specific error messages for permissions/storage issues, and guaranteed GPS mode restoration in finally block. Mounted state checks before setState.

### What's done (Phase 3 — offline maps, complete)
- `lib/services/offline_manager.dart`: Refactored to use MapLibre's native offline API:
  - `downloadRegion()` — wraps `downloadOfflineRegion()` with progress stream
  - `downloadRouteRegion()` — download tiles for buffered route corridor
  - `listRegions()`, `deleteRegion()` — wraps native region management
  - `estimateTileCount()`, `estimateSize()` — pre-download estimates
  - `setOffline()` — force MapLibre into offline mode
  - `clearAll()` — delete all offline regions
  - Tiles stored in MapLibre's native cache, served automatically when offline
- `lib/services/connectivity_service.dart`: Network status detection via `connectivity_plus`
- `lib/services/download_foreground_service.dart`: Android foreground service wrapper
  - Keeps app alive during downloads when screen is off or app is backgrounded
  - Persistent notification with progress updates ("Downloading map tiles... 47%")
  - Uses `flutter_foreground_task` with `dataSync` foreground service type
  - WiFi wake lock prevents radio from sleeping during download
- `lib/screens/offline_regions_screen.dart`: Region management UI
  - List all downloaded regions with zoom range and tile count
  - Delete individual regions or clear all
  - Dark theme consistent with rest of app
- `lib/widgets/download_progress_overlay.dart`: Map overlay during download
  - Progress bar with percentage, cancel button
  - Auto-dismisses on completion
- `lib/screens/map_screen.dart`: Offline UI additions:
  - Download button (cloud icon) in top-right control column
  - Bottom sheet: "Download visible area", "Download around route", "Manage offline regions"
  - Config dialog: name region, adjust zoom range (6–16), see tile count & size estimate
  - Offline indicator chip (orange "Offline" badge) when no network
  - Foreground service lifecycle tied to download start/stop/cancel
- `lib/utils/tile_calculator.dart`: Tile math utilities (unchanged from earlier)
- `android/app/src/main/AndroidManifest.xml`: Added `FOREGROUND_SERVICE_DATA_SYNC` permission and foreground task service declaration
- Tests: `test/tile_calculator_test.dart`, `test/offline_manager_test.dart` (updated for new API)

### What needs to happen next
1. **Device testing**: Test Phase 3 offline download flow on Redmi 14. See detailed checklist in `docs/TODO.md` under "Immediate Priorities (Phase 3 Device Testing)".
2. **Update docs**: Once testing complete, mark Phase 3 as fully done in ROADMAP.md
3. **Proceed to Phase 4**: WMS data (Italian orthophotos). Research phase — see `docs/TODO.md` "Phase 4 Planning" section for open questions and research needed.

## Conventions

- Use English for all code, comments, and documentation
- Dart naming: `lowerCamelCase` for variables/functions, `UpperCamelCase` for classes, `snake_case` for files
- Keep services stateless where possible; pass dependencies explicitly
- Prefer composition over inheritance
- Write TODO comments with context: `// TODO(phase2): implement GPX waypoint parsing`
- **Always commit and push** after completing work. Commit with a clear message, then `git push`.
