# AlpineNav - Claude Code Context

## Project Summary

AlpineNav is an offline-first outdoor navigation app for skitouring, hiking, and climbing. Primary focus on the Italian Alps. Built with Flutter + MapLibre GL (2D) with Mapbox reserved for 3D terrain in Phase 5.

**Philosophy**: Minimal, functional UI. No animations, no unnecessary features. Map fills the screen. Information density over whitespace. Inspired by ViewRanger's original simplicity.

## Tech Stack

- **Framework**: Flutter (Dart)
- **Mapping (2D)**: MapLibre GL for Flutter (`maplibre_gl`) + OpenFreeMap tiles
- **Mapping (3D, Phase 5)**: Mapbox Maps SDK (deferred until 3D terrain needed)
- **Platform**: Android first (no iOS until Android is solid)
- **Offline tiles**: MBTiles format (SQLite-based)
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

```bash
# Run on connected device/emulator
flutter run

# Run with verbose logging
flutter run -v

# Build APK
flutter build apk

# Run tests
flutter test

# Analyze code
flutter analyze

# Get dependencies
flutter pub get

# Check Flutter setup
flutter doctor
```

## Architecture Decisions

1. **MapLibre for 2D, Mapbox for 3D only**: MapLibre is open source, no API keys needed. Mapbox is deferred to Phase 5 for 3D terrain. If MapLibre ships mobile 3D terrain (expected late 2026), Mapbox may not be needed at all.
2. **Abstract the map layer**: `MapProvider` interface in `map_service.dart` allows swapping between MapLibre and Mapbox without touching the rest of the app. `MapLibreProvider` is the active implementation.
3. **Offline-first**: All features must work without network. Tile cache uses MBTiles (SQLite). Route data stored locally.
4. **Android-only**: Simpler setup, cheaper ($25 vs $99/year), no Mac needed.
5. **Minimal UI**: Map fills screen. Controls overlay minimally. No bottom nav bars, no card designs, no Material floating aesthetic. Muted colors, large touch targets (gloves).

## File Structure

```
lib/
  main.dart                    # App entry point
  screens/
    map_screen.dart            # Main map view (primary screen)
  services/
    map_service.dart           # Map provider abstraction
    location_service.dart      # GPS location handling
    offline_manager.dart       # Tile downloading and cache management
    gpx_service.dart           # GPX import/export/recording
  models/
    route.dart                 # Route/track data model
    waypoint.dart              # Waypoint data model
  utils/
    tile_calculator.dart       # Tile math (bbox to tile indices, etc.)
scripts/
  setup_env.sh                 # Cloud environment setup (Flutter + Android SDK + Gradle proxy)
  gradle_proxy.py              # Local proxy for Gradle in cloud environments
docs/
  ARCHITECTURE.md              # Technical architecture
  DATA_SOURCES.md              # Italian geoportal endpoints
  ROADMAP.md                   # Detailed feature roadmap
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
- `flutter test` — 18 tests passed
- `flutter build apk --debug` — **builds successfully** (181MB debug APK). Requires Android SDK setup (automated by `scripts/setup_env.sh`).

### What's been fixed since initial code
1. **Accuracy circle**: `CircleOptions.circleRadius` was receiving meters instead of pixels. Added `metersToPixels()` static method with ground-resolution formula. Accuracy circle now recalculates on zoom via `onCameraIdle()`.
2. **Missing `dart:math` import**: `Point` class needed explicit import from `dart:math` in `map_screen.dart`.
3. **Test file**: Default `widget_test.dart` referenced non-existent `MyApp` — replaced with `AlpineNavApp` smoke test.
4. **Tile source fallback**: Added `MapLibreProvider.fallbackStyleUrl` pointing to `demotiles.maplibre.org/style.json`.

### What needs to happen next
1. **Test on device**: Install APK on an Android device/emulator. Verify:
   - Map loads with OpenFreeMap bright tiles (if 403, switch to `fallbackStyleUrl` in `map_screen.dart`)
   - GPS blue dot appears at correct location
   - Accuracy circle scales correctly when zooming in/out
   - Reset-north and zoom-to-location buttons work
   - Coordinate chip shows lat/lon/altitude
2. **Proceed to Phase 3**: Offline tile download. Phase 2 (GPX import/export, route display, track recording) is implemented.

### Phase 2 readiness
- `lib/models/route.dart` and `lib/models/waypoint.dart` are stubs with field specs documented
- `lib/services/gpx_service.dart` is a stub with requirements documented
- `lib/utils/tile_calculator.dart` has working tile math, needs route-buffer functions for Phase 3
- `MapLibreProvider.addTrackLayer()` is implemented and ready for GPX polyline display

## Conventions

- Use English for all code, comments, and documentation
- Dart naming: `lowerCamelCase` for variables/functions, `UpperCamelCase` for classes, `snake_case` for files
- Keep services stateless where possible; pass dependencies explicitly
- Prefer composition over inheritance
- Write TODO comments with context: `// TODO(phase2): implement GPX waypoint parsing`
