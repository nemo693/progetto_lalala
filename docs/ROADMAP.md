# Roadmap

## Phase 1 — Foundation

**Goal**: A working app that displays a map and shows your location.

- [x] Flutter project initialization and MapLibre SDK setup
- [x] Display base map via MapLibre + OpenFreeMap (full screen)
- [x] GPS location display with accuracy circle
- [x] Basic map controls: pinch zoom, pan, rotate
- [x] Compass/north button (reset to north)
- [x] Zoom to current location button
- [x] Coordinate display (GPS position + altitude)

**Done when**: You can install the app, see a map, and see your blue dot moving.

## Phase 2 — Routes

**Goal**: Import, view, and record GPX tracks.

- [x] Import GPX files from device storage (file picker)
- [x] Parse GPX tracks and waypoints
- [x] Display track as polyline on map
- [x] Display waypoints as markers
- [x] Start/end markers for tracks
- [x] Auto-zoom to fit imported track
- [x] Track recording: start/stop/pause
- [x] Live stats during recording: distance, elapsed time, current elevation, elevation gain
- [x] Save recorded track as GPX
- [x] Route list screen (saved + imported)
- [x] Delete routes
- [ ] Export routes (share GPX file)

**Status**: ✅ Core features complete. Device testing in progress (Redmi 14). Export feature pending.

**Done when**: You can load a GPX from a planning tool, see it on the map, record your actual track, and compare them.

## Phase 3 — Offline Maps

**Goal**: Full map functionality without network.

- [x] Manual region download: draw rectangle, select zoom range, download tiles
- [x] Progress indicator during download (tile count, MB, estimated remaining)
- [x] Route-based download: select a saved route, specify buffer distance, download
- [x] Tile storage using MapLibre's native offline region API
- [x] Storage management screen: list cached regions, show size, delete
- [x] Offline indicator in UI (orange "Offline" badge when no network)
- [x] Graceful degradation: cached tiles shown automatically, MapLibre handles missing tiles
- [x] Background download support (Android foreground service keeps downloads alive)
- [x] Integration with MapLibre: tiles served automatically from native cache

**Status**: ✅ Complete. Awaiting device testing (Redmi 14) to verify download flow and offline functionality.

**Done when**: You can download a region at home, enable airplane mode, and navigate in the field using cached tiles. ✅ Implementation complete, device testing pending.

## Phase 4 — WMS Orthophotos

**Goal**: Italian orthophotos as an alternative base layer.

- [ ] WMS client: construct GetMap requests from tile coordinates
- [ ] PCN national orthophoto integration
- [ ] Cache WMS responses as MBTiles (same format as base map cache)
- [ ] Layer switcher UI: base map / orthophoto / hybrid overlay
- [ ] Regional WMS endpoint configuration (Veneto, Trentino, etc.)
- [ ] Opacity control for orthophoto overlay
- [ ] Pre-download orthophoto tiles for a region/route (same UI as Phase 3)

**Done when**: You can switch to orthophoto view, see real aerial imagery, and it works offline after downloading.

## Phase 5 — 3D Terrain (Mapbox)

**Goal**: Terrain visualization for route planning and awareness.

- [ ] Add Mapbox SDK alongside MapLibre (MapboxProvider behind MapProvider interface)
- [ ] Enable Mapbox terrain-RGB (hillshade + 3D extrusion)
- [ ] Terrain exaggeration slider
- [ ] Pitch/tilt gesture for 3D viewing angle
- [ ] Drape orthophoto layer over 3D terrain
- [ ] Custom DTM integration: load regional high-res DTM as terrain source
- [ ] Elevation profile for selected route (2D chart)
- [ ] Elevation query: tap a point, see elevation from terrain data

**Done when**: You can view your route in 3D with real terrain, draped with orthophotos, and see an elevation profile.

## Future Ideas (not planned)

These are explicitly out of scope but noted for reference:

- **Slope analysis**: Compute slope from DTM, shade steep areas (avalanche terrain)
- **Weather overlay**: Integrate weather radar or forecast data
- **Multi-day planning**: Link routes into multi-day itineraries
- **Collaborative routes**: Share routes with a group
- **iOS support**: Once Android is stable
- **Desktop/web viewer**: For route planning at home (Flutter web)
- **Custom map styles**: Dark mode map, winter-specific styling
- **Integration with Refugio booking systems**
- **Emergency features**: SOS coordinates display, what3words

## Development Principles

1. **Each phase must be complete and useful before starting the next.** No half-finished features.
2. **Test in the field** after each phase. Desk testing is insufficient for an outdoor app.
3. **Performance on mid-range Android devices.** Not everyone has a flagship phone.
4. **Battery consciousness.** GPS and map rendering are expensive. Provide controls to reduce polling frequency.
5. **Incremental complexity.** Start with the simplest implementation that works. Optimize when you have real usage data.
