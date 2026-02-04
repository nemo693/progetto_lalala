# AlpineNav - Claude Code Context

## Project Summary

AlpineNav is an offline-first outdoor navigation app for skitouring, hiking, and climbing. Primary focus on the Italian Alps. Built with Flutter + Mapbox Maps SDK.

**Philosophy**: Minimal, functional UI. No animations, no unnecessary features. Map fills the screen. Information density over whitespace. Inspired by ViewRanger's original simplicity.

## Tech Stack

- **Framework**: Flutter (Dart)
- **Mapping**: Mapbox Maps SDK for Flutter (`mapbox_maps_flutter`)
- **Platform**: Android first (no iOS until Android is solid)
- **Offline tiles**: MBTiles format (SQLite-based)
- **State management**: TBD (start simple, add if needed)

## Developer Context

The developer is experienced with:
- R, PostgreSQL, QGIS, GIS/remote sensing, geospatial data processing
- Python, bash, Linux
- Coordinate systems, projections, WMS/WMTS, DTM, tiles, raster processing

The developer is **new to**:
- Dart, Flutter, mobile development, Mapbox SDK
- Explain Flutter/Dart concepts, widget lifecycle, build patterns
- Do NOT explain GIS concepts (tiles, projections, WMS, DTM, coordinate systems)

## Feature Roadmap

### Phase 1 - Foundation
- Display base map (Mapbox Streets)
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

### Phase 5 - 3D Terrain
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

1. **Mapbox over MapLibre**: MapLibre lacks mobile 3D terrain (expected late 2026). Accept Mapbox's proprietary nature; free tier (50k MAU) is sufficient.
2. **Abstract the map layer**: Use a `MapProvider` interface so the mapping backend can be swapped to MapLibre later without rewriting the app.
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

## Key Documentation Links

- Mapbox Maps Flutter SDK: https://docs.mapbox.com/android/maps/guides/
- mapbox_maps_flutter on pub.dev: https://pub.dev/packages/mapbox_maps_flutter
- Mapbox offline maps: https://docs.mapbox.com/android/maps/guides/offline/
- Flutter docs: https://docs.flutter.dev/
- Dart language: https://dart.dev/language
- GPX format spec: https://www.topografix.com/gpx.asp
- MBTiles spec: https://github.com/mapbox/mbtiles-spec

## Secrets

Mapbox access token goes in:
- `android/app/src/main/res/values/mapbox_access_token.xml` (for native SDK init)
- Referenced in Dart code via environment or config

**NEVER commit secrets.** The `.gitignore` excludes token files. Use `--dart-define` or a `.env` file for local development.

## Conventions

- Use English for all code, comments, and documentation
- Dart naming: `lowerCamelCase` for variables/functions, `UpperCamelCase` for classes, `snake_case` for files
- Keep services stateless where possible; pass dependencies explicitly
- Prefer composition over inheritance
- Write TODO comments with context: `// TODO(phase2): implement GPX waypoint parsing`
