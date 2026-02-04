# Roadmap

## Phase 1 — Foundation

**Goal**: A working app that displays a map and shows your location.

- [ ] Flutter project initialization and Mapbox SDK setup
- [ ] Display Mapbox Streets base map (full screen)
- [ ] GPS location display with accuracy circle
- [ ] Basic map controls: pinch zoom, pan, rotate
- [ ] Compass button (reset to north)
- [ ] Zoom to current location button
- [ ] Coordinate display (current center or GPS position)

**Done when**: You can install the app, see a map, and see your blue dot moving.

## Phase 2 — Routes

**Goal**: Import, view, and record GPX tracks.

- [ ] Import GPX files from device storage (file picker)
- [ ] Parse GPX tracks and waypoints
- [ ] Display track as polyline on map
- [ ] Display waypoints as markers
- [ ] Start/end markers for tracks
- [ ] Auto-zoom to fit imported track
- [ ] Track recording: start/stop/pause
- [ ] Live stats during recording: distance, elapsed time, current elevation, elevation gain
- [ ] Save recorded track as GPX
- [ ] Route list screen (saved + imported)
- [ ] Delete routes
- [ ] Export routes (share GPX file)

**Done when**: You can load a GPX from a planning tool, see it on the map, record your actual track, and compare them.

## Phase 3 — Offline Maps

**Goal**: Full map functionality without network.

- [ ] Manual region download: draw rectangle, select zoom range, download tiles
- [ ] Progress indicator during download (tile count, MB, estimated remaining)
- [ ] Route-based download: select a saved route, specify buffer distance, download
- [ ] Tile storage in MBTiles format
- [ ] Storage management screen: list cached regions, show size, delete
- [ ] Offline indicator in UI (icon when no network)
- [ ] Graceful degradation: cached tiles shown, missing tiles handled cleanly
- [ ] Background download support (continue when app is backgrounded)

**Done when**: You can download a region at home, enable airplane mode, and navigate in the field using cached tiles.

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

## Phase 5 — 3D Terrain

**Goal**: Terrain visualization for route planning and awareness.

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
