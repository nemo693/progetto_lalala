# TODO and Open Points

**Last updated**: 2026-02-11

## Immediate Priorities (Phase 3 Device Testing)

### Critical: Device Testing Required
Phase 3 (offline maps) is code-complete but **not yet tested on device**. Must verify on Redmi 14:

1. **Download visible area flow**
   - [ ] Open download bottom sheet
   - [ ] Configure region name and zoom range
   - [ ] Verify tile count and size estimates are reasonable
   - [ ] Start download → verify foreground notification appears
   - [ ] Verify progress bar updates in overlay
   - [ ] Lock screen during download → verify it continues
   - [ ] Return to app → verify progress persists
   - [ ] Wait for completion → verify success message
   - [ ] Enable airplane mode → verify tiles render from cache

2. **Download around route flow**
   - [ ] Import or load a saved GPX route
   - [ ] Open download bottom sheet → select "Download around route"
   - [ ] Choose route from list
   - [ ] Configure buffer distance (default 2km)
   - [ ] Verify tile estimate for buffered corridor
   - [ ] Download → verify foreground service keeps it alive with screen off
   - [ ] Check offline regions screen → verify corridor region listed

3. **Offline regions management**
   - [ ] Navigate to "Manage offline regions" screen
   - [ ] Verify all downloaded regions appear with correct metadata
   - [ ] Delete individual region → verify tiles no longer render offline
   - [ ] Download multiple regions → verify storage totals add up
   - [ ] "Clear all" → verify all regions deleted

4. **Offline indicator**
   - [ ] With downloaded region: enable airplane mode
   - [ ] Verify orange "Offline" badge appears
   - [ ] Pan around cached area → tiles render
   - [ ] Pan outside cached area → verify graceful degradation (blank or lower zoom)
   - [ ] Re-enable network → verify "Offline" badge disappears

5. **Foreground service behavior**
   - [ ] Start download → verify persistent notification appears ("Downloading map tiles...")
   - [ ] Notification shows progress percentage
   - [ ] Lock screen → verify download continues
   - [ ] Swipe away notification → verify download cancels
   - [ ] Background app → verify download survives
   - [ ] Kill app → verify download stops (no orphaned notifications)

### Known Risks

- **WMS tile deadlock (already fixed)**: MapLibre's `downloadOfflineRegion()` had a deadlock bug when downloading from WMS sources due to semaphore misuse. Fixed in commit `35d5539` by replacing broken semaphore with queue-based concurrency control.
- **Tile server rate limiting**: OpenFreeMap has no documented rate limits, but aggressive parallel downloads could trigger throttling. Monitor during testing. If needed, reduce `maxConcurrentDownloads` in `OfflineManager`.
- **Storage exhaustion**: Large zoom ranges (6–16 over Dolomites) can generate 100K+ tiles (5+ GB). Estimate display warns users, but verify it's accurate.
- **Battery drain**: Foreground service with wake lock prevents sleep. Long downloads on battery could drain significantly. Consider adding battery level check or user warning.

## Phase 2 Remaining Work

### Export Routes (Not Started)
**Status**: All core route features complete except GPX export/share.

**Requirements**:
- [ ] Add "Share" button to route list items
- [ ] Implement `GpxService.exportRoute(Route route, String outputPath)`
- [ ] Use Flutter's `share_plus` package to share GPX file (or allow user to choose save location)
- [ ] Handle permissions (WRITE_EXTERNAL_STORAGE on Android <10, scoped storage on 10+)
- [ ] Add UI to route details screen or long-press menu

**Estimated effort**: 2–3 hours

**Dependencies**: None (can be done anytime)

**Priority**: Low (import and recording work; export is a "nice to have" for sharing with others)

## Phase 4 Planning (WMS Orthophotos)

### Research Needed Before Starting

1. **WMS Endpoint Selection**
   - [ ] Survey Italian regional WMS endpoints (see `docs/DATA_SOURCES.md`)
   - [ ] Test GetCapabilities and GetMap requests for each
   - [ ] Verify coordinate systems (most use EPSG:3857 or EPSG:4326)
   - [ ] Check tile size limits and format support (PNG vs JPEG)
   - [ ] Document authentication requirements (most are open, but some regions require API keys)

2. **Tile Caching Strategy**
   - [ ] Decide: cache WMS responses as MapLibre raster source, or write custom MBTiles?
   - [ ] MapLibre approach: simpler, but less control over cache eviction
   - [ ] MBTiles approach: full control, compatible with QGIS, but requires custom tile server or MapLibre RasterSource from MBTiles
   - [ ] Benchmark: how does MapLibre's native raster cache handle large offline WMS tiles?

3. **Layer Switching UI**
   - [ ] Design: bottom sheet with layer list? Floating button? Map style picker?
   - [ ] Options: base map only, orthophoto only, hybrid (semi-transparent orthophoto over base map)
   - [ ] Opacity slider for hybrid mode
   - [ ] Remember user preference across sessions

4. **Performance Considerations**
   - [ ] WMS requests are slower than vector tile CDNs (regional servers, larger payloads)
   - [ ] Raster tiles are larger than vector tiles (expect 50–200 KB per tile vs 10–30 KB)
   - [ ] Pre-download will take significantly longer
   - [ ] Consider progressive download: low zoom first, then refine

### Open Questions

- **Do Italian WMS endpoints support WMTS?** WMTS (tiled) is faster than WMS (on-demand rendering). Check if endpoints like PCN or regional geoportals offer WMTS. If yes, use that instead.
- **How to handle region boundaries?** Orthophoto coverage often stops at administrative borders. Should we auto-switch to base map outside coverage, or show a "no data" indicator?
- **Color correction?** Orthophotos from different years/regions may have different color balance. Do we need normalization, or accept the inconsistency?

## Phase 5 Planning (3D Terrain)

**Status**: Deferred until Phases 1–4 are field-tested and stable.

### Decision Point: MapLibre 3D vs Mapbox

- **MapLibre Native**: 3D terrain support expected late 2026 (GL JS already has it, Native SDK in progress)
- **Mapbox**: Available now, but requires API key and usage fees (free tier: 100K tile requests/month)

**Decision**: Wait for MapLibre 3D terrain to stabilize. If not available by mid-2026, evaluate Mapbox. The `MapProvider` abstraction makes switching easy.

### Technical Unknowns

- **Custom DTM integration**: How to load regional high-res DTM (e.g., Trentino 2.5m DTM) as a terrain source? Mapbox supports terrain-RGB tiles; MapLibre may use a different format.
- **Draping orthophotos**: Can we overlay WMS raster tiles on 3D terrain? Mapbox supports this; MapLibre's roadmap unclear.
- **Performance on mid-range devices**: 3D rendering is GPU-intensive. Test on Redmi 14 (Snapdragon 4 Gen 2) to set baseline expectations.

## Code Quality and Technical Debt

### No Current Technical Debt
`flutter analyze` and `flutter test` are clean. No `TODO`, `FIXME`, or `HACK` comments in codebase.

### Potential Improvements (Not Urgent)

1. **State management**: Currently using `setState()` everywhere. If app complexity grows (e.g., multi-screen navigation, background sync), consider `riverpod` or `bloc`. Not needed yet.

2. **Unit test coverage**: Current tests cover tile math and basic widget smoke tests. Could add:
   - `GpxService` parsing edge cases (malformed GPX, missing elevation, etc.)
   - `RouteStorageService` CRUD operations
   - `LocationService` permission flow (using mocks)

3. **Error telemetry**: No crash reporting or analytics. If app is released publicly, add Firebase Crashlytics or Sentry.

4. **Logging**: Currently using `print()` statements. Consider structured logging (e.g., `logger` package) for easier debugging.

5. **Accessibility**: No screen reader support, no semantic labels. If app is used by visually impaired users (unlikely for a map app), add `Semantics` widgets.

## Known Issues and Workarounds

### Windows Development Environment

1. **Flutter SDK path with spaces** (`C:\Users\Emilio Dorigatti\flutter`)
   - Causes `update_engine_version.ps1` failure on first run after cache clear
   - Workaround: run `flutter run` twice (first fails, second succeeds)
   - Permanent fix: move SDK to `C:\flutter`

2. **`objective_c` build hook crash**
   - Transitive dependency via `path_provider` → `path_provider_foundation`
   - Workaround: `dependency_overrides` pins `path_provider_foundation: 2.4.0` (pre-FFI version)
   - Safe because `path_provider_foundation` is iOS/macOS only

### MapLibre SDK

1. **GeoJSON format requirements** (fixed)
   - `addSource()` expects `FeatureCollection`, not bare `Feature`
   - Wrapped all GeoJSON in `FeatureCollection` in `MapLibreProvider.addTrackLayer()`

2. **Duplicate layer crash** (fixed)
   - Adding a layer with an existing ID crashes
   - Now call `removeLayer(id)` before `addLayer()` and wrap in try/catch

3. **WMS download deadlock** (fixed in commit `35d5539`)
   - MapLibre's `downloadOfflineRegion()` had semaphore deadlock when downloading WMS tiles
   - Replaced broken semaphore logic with queue-based concurrency control
   - Monitor for regressions if MapLibre GL Flutter updates

### Android

1. **Foreground service notification persistence**
   - If app is killed while download is in progress, notification may persist
   - Need to test: does `FlutterForegroundTask.stopService()` clean up reliably?
   - If not, add `onDestroy()` handler in `DownloadForegroundService`

## Documentation Gaps

### Missing Documentation

1. **User manual**: No end-user documentation. If app is shared, add:
   - How to import GPX files
   - How to record a track
   - How to download offline maps
   - How to manage storage

2. **Developer onboarding**: `CLAUDE.md` is comprehensive, but assumes familiarity with the project. Could add:
   - "How to build and run" quick-start
   - Architecture diagram (visual)
   - Testing strategy

3. **WMS endpoint catalog**: `docs/DATA_SOURCES.md` exists but may be outdated. Needs:
   - Verified endpoints for all Italian regions
   - Example GetMap requests
   - Coverage maps (which regions have orthophotos?)

### Documentation to Update After Phase 3 Testing

Once Phase 3 device testing is complete:
- [ ] Update `CLAUDE.md` "Current Status & Next Steps" → mark Phase 3 as fully complete
- [ ] Update `docs/ROADMAP.md` → Phase 3 status to "✅ Complete, field-tested"
- [ ] Update `docs/ARCHITECTURE.md` → document offline manager implementation details
- [ ] Add screenshots to README (map view, offline download, route display)

## Future Feature Ideas (Not Planned)

These are not in scope for MVP, but noted for future consideration:

### High Value, Low Effort
- **Dark mode map style**: OpenFreeMap has a dark style (`styles/dark`). Add a toggle. (1 hour)
- **Compass rose on map**: Show N/S/E/W labels around map edge. Useful for navigation. (2 hours)
- **Distance measurement tool**: Tap two points, show straight-line distance. (2 hours)
- **Coordinate format picker**: Currently shows decimal degrees. Add DMS, UTM, MGRS. (3 hours)

### High Value, High Effort
- **Offline search**: Geocoding without network (requires local place name database). (20+ hours)
- **Route planning**: Tap waypoints on map, generate route. (40+ hours)
- **Integration with Italian refuge booking systems**: Auto-populate waypoints with refuge info. (60+ hours)

### Low Value (Avoid Feature Creep)
- **Social features**: Share routes, follow friends. (Adds complexity, moderation burden)
- **Weather overlay**: Requires API key, data fees, and constant updates. (Use external app instead)
- **Turn-by-turn navigation**: Out of scope. This is a map viewer, not a navigation app.

## Testing Strategy

### Current Testing
- **Unit tests**: Tile math (`tile_calculator_test.dart`), offline manager (`offline_manager_test.dart`)
- **Widget smoke test**: App launches without crash (`widget_test.dart`)
- **Static analysis**: `flutter analyze` (0 issues)

### Gaps
- **Integration tests**: No end-to-end tests (e.g., "import GPX → display on map → zoom to fit")
- **Device testing**: Phase 1 and 2 tested on Redmi 14. Phase 3 awaiting testing.
- **Performance testing**: No benchmarks for large GPX files (10K+ points), large tile downloads (100K+ tiles), or 3D rendering.

### Testing TODO
- [ ] Add integration tests for critical flows (GPX import, track recording, offline download)
- [ ] Benchmark GPX parsing for large files (use isolates if >1 second)
- [ ] Benchmark tile download throughput (tiles/sec, MB/sec)
- [ ] Test on low-end device (e.g., Android Go) to set minimum requirements

## Questions for User

1. **Export format**: Should route export support formats other than GPX? (KML for Google Earth, GeoJSON for web maps?)
2. **Offline map expiration**: Should cached tiles expire after N days/months? Or keep indefinitely until user deletes?
3. **Background sync**: Should the app auto-update cached tiles when on WiFi? Or only manual refresh?
4. **Battery optimization**: Should we warn users before starting large downloads on battery, or enforce WiFi-only?
5. **Privacy**: Should GPS tracks be stored with full timestamp precision, or anonymize (round to nearest minute) for privacy?

## Next Steps (Priority Order)

1. **Test Phase 3 on device** (see checklist above) — **CRITICAL, BLOCKING PHASE 4**
2. **Fix any issues found in device testing**
3. **Update documentation** to mark Phase 3 complete
4. **Research WMS endpoints** for Phase 4 (see `docs/DATA_SOURCES.md`)
5. **Decide on WMS caching strategy** (MapLibre native vs custom MBTiles)
6. **Implement Phase 4 WMS client and layer switching**
7. **Field test with orthophotos** (verify performance, usability)
8. **Phase 2 export feature** (low priority, can be done anytime)

---

**Status Summary**:
- ✅ Phase 1: Complete, field-tested
- ✅ Phase 2: Complete (except export), field-tested
- ⚠️ Phase 3: Code complete, **device testing pending**
- 🔜 Phase 4: Research phase
- 🔮 Phase 5: Deferred until 2026 H2
