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

### What's done (Phase 1 code — not yet build-tested)
- `pubspec.yaml`: MapLibre GL (`maplibre_gl: ^0.25.0`) replaces Mapbox
- `lib/services/map_service.dart`: `MapProvider` interface + `MapLibreProvider` implementation (camera, track layers, location marker, reset north)
- `lib/services/location_service.dart`: Full implementation (permission flow, one-shot position, streaming GPS, configurable accuracy)
- `lib/screens/map_screen.dart`: Full-screen MapLibre map with OpenFreeMap bright tiles, GPS blue dot with accuracy circle, reset-north button, zoom-to-location button, coordinate/altitude chip, error banner for permission issues. Default camera on Dolomites (46.5, 11.35)
- `scripts/setup_env.sh`: Cloud env setup (Flutter install, android scaffold, pub get — no tokens needed)
- `.claude/settings.json`: SessionStart hook wired up
- All docs updated to reflect MapLibre + OpenFreeMap

### What needs to happen next
1. **Build-test Phase 1**: Run in a cloud session with Flutter available (or locally). The code has not been compiled yet. Expect possible API mismatches with `maplibre_gl` — the circle annotation API in particular may need adjustment.
2. **Android scaffold**: `flutter create --org com.alpinenav --project-name alpinenav --platforms android .` must be run before building. The setup script handles this in cloud sessions. Locally the developer runs it once.
3. **Android permissions**: `AndroidManifest.xml` needs `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`. MapLibre may add these automatically, but verify after scaffold generation.
4. **Kotlin version**: `maplibre_gl` requires Kotlin 2.1.0+. May need to update `android/settings.gradle` after scaffold generation.
5. **Known risks**:
   - `CircleOptions.circleRadius` in MapLibre GL uses screen pixels, not meters. The accuracy circle will need conversion from meters to pixels at the current zoom level. This will need fixing after first visual test.
   - OpenFreeMap `bright` style URL may not resolve (was 403 during doc fetch). Fallback: `https://tiles.openfreemap.org/styles/dark` or `https://demotiles.maplibre.org/style.json`.

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
