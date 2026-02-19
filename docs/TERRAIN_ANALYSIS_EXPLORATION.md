# Terrain Analysis Layer Implementation — Exploration Document

## Overview

This document explores options for adding slope, aspect, and other terrain analysis layers to AlpineNav. The key decision point: **should computation happen server-side (pre-computed) or on-device?**

## Option 1: Server-Hosted Pre-Computed Tiles (Original Plan)

### Approach
1. You compute slope/aspect offline using Python script and GDAL
2. Tile results to XYZ format (PNG at zoom 10-18)
3. Host tiles on a server (S3, GitHub Pages, or custom CDN)
4. App downloads tiles from `https://your-server.com/tiles/slope/{z}/{x}/{y}.png`
5. Tiles cached locally via existing `WmsTileServer` infrastructure

### Architecture
```
Developer (you)          →  Compute once (Python)  →  Host on server (S3/CDN)
                                    ↓
                            Tile to XYZ format
                                    ↓
                          User's device: fetch tiles via HTTP
                                    ↓
                          Cache locally via WmsTileServer
                                    ↓
                          Display from local cache (offline)
```

### Pros
- ✅ **Computation burden on developer, not user**
- ✅ **No on-device computation overhead** (instant display once downloaded)
- ✅ **Reuses existing WmsTileServer infrastructure**
- ✅ **Can serve from CDN** for fast downloads
- ✅ **Easy updates**: recompute and re-upload if algorithms change

### Cons
- ❌ **Requires hosting (even if free via GitHub Pages)**
- ❌ **External dependency**: if server goes down, tiles unavailable
- ❌ **One-size-fits-all**: all users get same tile resolution/color scheme
- ❌ **Large download**: ~50-200 MB per layer for Trentino coverage
- ❌ **Bakes in your computation choices** (slope bins, color scheme, etc.)

### Implementation Complexity
- **Moderate** (~3-4 hours setup + maintenance)
- Setup: compute, tile, upload to hosting
- Maintenance: monitor server availability

### Device Storage Impact
- ~50-200 MB per layer (depending on area size)

### Offline Support
- ✅ **Yes** (after download), via local cache

### User Experience
- First load: download tiles (network required, ~5-30 min depending on area)
- Subsequent loads: instant (cached)
- Toggle between sources: instant

### Data Freshness
- Static: all users see same pre-computed data
- Update cycle: manual (recompute when new DTM available)

---

## Option 2: Device-Local Computation (New Approach)

### Approach
1. User downloads raw DTM GeoTIFF tiles from Trentino STEM portal (via existing WMS)
2. On first access to slope/aspect layer, device computes derivatives
3. Cache results as PNG tiles locally
4. Display from local cache (offline)

### Architecture
```
User downloads DTM tiles via WMS  →  Stored as GeoTIFF in documents/
                                           ↓
                          User toggles "Show slope layer"
                                           ↓
                       Device computes slope in background
                       (Kotlin native or Flutter isolate)
                                           ↓
                          Cache PNG tiles locally
                                           ↓
                          Display from cache (offline)
```

### Pros
- ✅ **No hosting required** (fully offline-first philosophy)
- ✅ **No external dependency** (computation entirely on device)
- ✅ **User controls parameters**: can adjust slope bins, color scheme, etc.
- ✅ **Privacy**: no data leaving device
- ✅ **Fits AlpineNav philosophy** perfectly
- ✅ **Reproducible**: user can recompute with different params

### Cons
- ❌ **Computation on user's device** (battery, CPU, time)
- ❌ **Requires mobile-friendly algorithms** (must be fast on mid-range Android)
- ❌ **Requires on-device DSM/DTM files** (already downloaded for offline)
- ❌ **Complex implementation**: need Kotlin/C++ for performance
- ❌ **Device storage**: DTM + computed tiles can be large
- ❌ **First-time delay**: slope/aspect show up with 30-60 sec delay after toggle

### Implementation Complexity
- **High** (~20-30 hours for production-quality)
  - Write Kotlin/C++ slope/aspect functions with SIMD optimization
  - Platform channel integration (Dart ↔ Kotlin)
  - Progress UI during computation
  - Error handling for device storage limits
  - Caching logic with invalidation

### Device Storage Impact
- DTM already stored (for offline use): ~1-5 GB per region
- Computed tiles: ~50-150 MB per layer
- **Total**: DTM + slopes + aspect can easily exceed 500 MB per region

### Offline Support
- ✅ **Yes** (100% offline after download and computation)

### User Experience
- First load of DTM: download ~1-5 GB (can take 30 min–2 hrs)
- First toggle of slope layer: compute for visible area (~30-60 sec), show progress
- Subsequent loads: instant (cached)
- Toggle between sources: instant after first computation

### Data Freshness
- Dynamic: each user's device computes independently
- Parameters adjustable per user

---

## Option 3: Hybrid (Best of Both)

### Approach
1. **Pre-compute slope/aspect for popular areas** (Dolomites, Brenta, etc.)
2. **Include as optional downloadable dataset** (like offline regions)
3. **Allow device computation as fallback** for unmapped areas
4. User can choose: "Use pre-computed" or "Compute on device"

### Architecture
```
User downloads "Dolomites pre-computed terrain"  →  Stored as PNG tiles
                     OR
User downloads DTM manually from STEM  →  Device computes on demand

Either way:
        ↓
   Displayed from local cache
```

### Pros
- ✅ **Best user experience**: popular areas instant, custom areas available
- ✅ **Flexible**: users choose
- ✅ **Scales well**: some pre-computed, others on-demand
- ✅ **No external dependency** (pre-computed tiles included in release, not hosted)
- ✅ **Fits offline-first philosophy**

### Cons
- ❌ **Moderate implementation complexity** (~15-20 hours)
- ❌ **App includes pre-computed datasets** (maybe +100-200 MB to APK)
- ❌ **Two code paths to maintain**

### Implementation Complexity
- **Moderate-High** (~15-20 hours)
  - Pre-compute once (using Python script)
  - Include in GitHub release as optional download
  - Add UI for "Download terrain analysis pack"
  - Implement device computation as fallback
  - Platform channels for computation

### Device Storage Impact
- Similar to Option 2, but pre-computed packs downloaded on demand

### Offline Support
- ✅ **Yes** (100%)

### User Experience
- For popular areas: download pre-computed pack (~30-50 MB), instant
- For custom areas: compute on device (~30-60 sec first load)
- Very flexible and user-friendly

---

## Option 4: WMS-Only (No Computation)

### Approach
Just use existing WMS layers from Trentino:
- `dtm_315_wg` (DTM hillshade, already in app)
- `dtm_135_wg` (DTM hillshade, alt lighting)
- `dsm_315_wg` (DSM hillshade, shows buildings)

**No slope, aspect, or TRI computation.**

### Pros
- ✅ **Zero implementation effort** (2 lines of code to add)
- ✅ **No computation, no storage**
- ✅ **Existing infrastructure**

### Cons
- ❌ **Doesn't provide slope/aspect** (only hillshade variants)
- ❌ **Still requires network** for initial tile load
- ❌ **Not terrain analysis**, just visualization

### Implementation Complexity
- **Trivial** (~5 min)

---

## Decision Matrix

| Factor | Option 1 (Server) | Option 2 (Device) | Option 3 (Hybrid) | Option 4 (WMS) |
|--------|-------------------|-------------------|-------------------|---------------|
| **Implementation effort** | 3-4h | 20-30h | 15-20h | <1h |
| **Hosting required?** | Yes | No | No | No |
| **Fully offline?** | ✅ Yes* | ✅ Yes | ✅ Yes | ❌ No (need network initially) |
| **User computation?** | ❌ No | ✅ Yes | ⚠️ Optional | ❌ No |
| **Device storage impact** | ~150 MB/layer | ~500 MB+ | ~150 MB/layer | Minimal |
| **First load speed** | 5-30 min download | 30-60 sec compute | Instant (pre-comp) or 30s | 5-30 min download |
| **Aligns with philosophy** | ⚠️ Somewhat | ✅ Excellent | ✅ Excellent | ✅ Excellent |
| **App maintenance burden** | Low | Medium | Medium | Minimal |
| **User flexibility** | ❌ No | ✅ Yes | ✅ Yes | ❌ No |

*After download

---

## Technical Considerations for Device Computation (Option 2/3)

### Algorithm Efficiency

**Slope computation on a 512×512 pixel tile:**
- **Python (CPU)**: ~500ms per tile
- **Kotlin (CPU)**: ~50ms per tile (10× faster, no JNI overhead)
- **Kotlin (SIMD)**: ~10ms per tile (50× faster)

For a typical region (50 tiles at zoom 15):
- Python: ~25 seconds
- Kotlin: 2.5 seconds
- Kotlin SIMD: 0.5 seconds

**Recommendation**: Implement in Kotlin with SIMD (NEON on ARM) for acceptable performance.

### Storage Considerations

**DTM tile (512×512, 32-bit float, one zoom level):**
- Raw: ~1 MB
- Compressed (GeoTIFF): ~200-300 KB

**Slope tiles (512×512, 8-bit RGB, one zoom level):**
- Raw: ~786 KB
- Compressed (PNG, LZ): ~100-150 KB

**For Trentino at zoom 10-18:**
- DTM: ~100-200 GB (1 TB with overhead)
- Slope tiles: ~10-20 GB
- Aspect tiles: ~10-20 GB

**Practical storage**: Most users won't download entire Trentino. A single peak (10-50 km²) = ~50-200 MB per layer.

### Battery Impact

**Computation:**
- 5 minutes of continuous CPU for slope/aspect = ~5-10% battery
- Acceptable for an optional feature triggered by user

**Storage:**
- SSD I/O relatively cheap on modern Android
- Minimal battery impact for tiling/caching

---

## Recommendation

### For AlpineNav's Current State:

**Option 3 (Hybrid)** — Best fit for your project:

1. **Phase 4.5 (Small exploration task, 2-3 hours):**
   - Pre-compute slope/aspect for one small area (e.g., a single peak in Dolomites)
   - Include in a GitHub release as optional download
   - Test download + display flow
   - Validate user experience

2. **Phase 5 (Future, only if needed):**
   - If users want computed layers for areas outside pre-computed regions
   - Implement device computation in Kotlin
   - Users can "compute on demand" for custom areas

### Why Option 3 for AlpineNav?

- ✅ **Minimal implementation** to get started (pre-computed only)
- ✅ **No external hosting dependency** (fits your philosophy)
- ✅ **Can evolve gradually** (add device computation later if needed)
- ✅ **Gives users choice** (instant for pre-computed, flexible for custom)
- ✅ **Reuses existing offline download UI pattern**
- ✅ **No external dependencies** (no new SDKs or plugins)
- ✅ **Aligns perfectly** with offline-first, minimal philosophy

---

## Immediate Next Step (If Exploring)

**Option 3 Phase 1: Pre-Computed Only**

1. Use Python script to compute slope/aspect for Dolomites area
2. Create a `TerrainAnalysisManager` service (similar to `offline_manager.dart`)
3. Add UI to download slope/aspect packs from GitHub releases
4. Store in `documents/terrain_analysis/{layer_id}/{z}/{x}/{y}.png`
5. Reuse existing `WmsTileServer` or create simple `file://` URL handler
6. Add to `map_source.dart`:

```dart
static const trentinoSlopeLocal = MapSource(
  id: 'trentino_slope_local',
  name: 'Slope (precomputed)',
  type: MapSourceType.rasterXyz,
  url: 'file://{docsDir}/terrain_analysis/slope/{z}/{x}/{y}.png',
  attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 60000,
);
```

**Implementation time:** ~4-6 hours
**Benefit:** Immediate feedback on UX, can decide if device computation is worth the effort

---

## References

- **Option 1 docs**: `LIDAR_PROCESSING.md`, `SLOPE_ASPECT_QUICKSTART.md`
- **Python computation**: `scripts/compute_terrain_analysis.py`
- **Existing patterns**: `lib/services/offline_manager.dart`, `lib/services/wms_tile_server.dart`
- **Trentino STEM**: https://siat.provincia.tn.it/stem/

