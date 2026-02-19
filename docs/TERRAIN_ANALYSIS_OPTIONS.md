# Terrain Analysis for AlpineNav — Options Summary

## Quick Navigation

You asked: *"Can't the device compute these locally? Do I have to host them?"*

**Answer: No, you don't have to host. You have options.**

### Choose Your Path:

1. **[Just use existing WMS](`#option-4-wms-only`)** — Easiest (5 min)
   - Use hillshade variants already available from Trentino
   - No slope/aspect, but DTM visualization

2. **[Pre-computed local](`#option-3-hybrid-recommended`)** — Balanced (4-6 hours)
   - You compute slope/aspect once
   - Include in app or GitHub release
   - Users download and use locally
   - **← Recommended starting point**

3. **[Device-computed](`#option-2-device-local-computation`)** — Advanced (20-30 hours)
   - User's device computes from downloaded DTM
   - No hosting, 100% offline-first
   - More work, but perfect fit for your philosophy

4. **[Server-hosted](`#option-1-server-hosted`)** — Traditional (3-4 hours + hosting)
   - You host tiles on CDN
   - Users download from web
   - Not recommended (external dependency)

---

## Option 1: Server-Hosted

**You compute once, host on server, users download from web.**

See: `LIDAR_PROCESSING.md`, `SLOPE_ASPECT_QUICKSTART.md`

### Implementation
1. Download DTM from Trentino STEM portal
2. Compute slope/aspect with Python script
3. Tile to XYZ format
4. Host on S3, GitHub Pages, or CDN
5. Add URL to `map_source.dart`

### Pros
- Computation burden on you, not users
- Fast tile delivery via CDN
- One-size-fits-all (easy to deploy)

### Cons
- ❌ **Requires hosting** (not true offline-first)
- ❌ External dependency (if server down, tiles unavailable)
- ❌ Contradicts AlpineNav philosophy (offline-first, minimal dependencies)

### Time Investment
- **Setup**: 3-4 hours (compute + upload)
- **Maintenance**: Low (static tiles)
- **Long-term cost**: Server hosting (~$0.50-2/month)

---

## Option 2: Device-Local Computation

**User downloads DTM, device computes slope/aspect locally.**

See: `DEVICE_LOCAL_COMPUTATION.md`

### Implementation
1. User downloads DTM from Trentino STEM (via existing offline downloader)
2. User toggles "Show slope layer"
3. Device computes slope from DTM in background
4. Cache results as PNG tiles locally
5. Display from cache (fully offline)

### Pros
- ✅ **No hosting required** — fully offline-first
- ✅ **No external dependencies** — computation on device
- ✅ **Perfect alignment** with AlpineNav philosophy
- ✅ User controls parameters (slope thresholds, colors, etc.)
- ✅ Privacy (no data leaving device)

### Cons
- ❌ Computation on user's device (battery, CPU, time)
- ❌ Complex implementation (Kotlin + SIMD for performance)
- ❌ First-load delay (~30-60 sec per region)
- ❌ Device storage (DTM + computed tiles = 500-800 MB per region)

### Time Investment
- **Prototype**: 4-6 hours (basic Kotlin computation)
- **Production**: 20-30 hours (SIMD, progress UI, error handling)
- **Maintenance**: Medium (debugging, device compatibility)

### Performance (Estimated)
- First computation: 30-60 seconds per region
- Storage: 500-800 MB per region
- Battery: ~5-10% per computation session
- Subsequent loads: instant (cached)

---

## Option 3: Hybrid (Recommended)

**You pre-compute popular areas, users can compute custom areas on-device.**

See: `TERRAIN_ANALYSIS_EXPLORATION.md` (section "Option 3")

### Phase 1: Pre-Computed Only (4-6 hours)

1. Compute slope/aspect for popular areas (Dolomites, Brenta, etc.) using Python
2. Include in GitHub release as optional download
3. Users download "Dolomites terrain pack" (~50-100 MB)
4. Store locally and display (no hosting required)

### Phase 2 (Future): Add Device Computation (20-30 hours)

If users request: implement on-device computation for unmapped areas.

### Pros
- ✅ **Best user experience**: popular areas instant, custom areas available
- ✅ **Minimal initial effort**: pre-computed only
- ✅ **No external hosting** (fits offline-first philosophy)
- ✅ **Scalable**: evolve to device computation if demand justifies
- ✅ **Users choose**: instant (pre-computed) or flexible (computed)

### Cons
- ⚠️ App includes datasets (~100-200 MB for pre-computed packs)
- ⚠️ Two code paths to maintain (later)

### Time Investment
- **Phase 1**: 4-6 hours (pre-computed only)
- **Phase 2** (if needed): 20-30 hours (add device computation)

---

## Option 4: WMS-Only

**Just use existing Trentino WMS layers (hillshade variants).**

See: `map_source.dart` (already has `trentinoLidarShading`)

### Add in 5 minutes:

```dart
static const trentinoLidarShading135 = MapSource(
  id: 'trentino_lidar_135',
  name: 'LiDAR Hillshade (135°)',
  type: MapSourceType.wms,
  wmsBaseUrl: 'https://siat.provincia.tn.it/geoserver/stem/dtm_135_wg/wms',
  wmsLayers: 'dtm_135_wg',
  // ... rest same as existing trentinoLidarShading
);
```

### Pros
- ✅ Trivial to add (2 lines of code)
- ✅ No hosting, no computation
- ✅ Reuses existing WMS infrastructure

### Cons
- ❌ **Not terrain analysis** — only hillshade visualization
- ❌ No slope or aspect data
- ❌ Still requires network for initial tile load

---

## Decision Guide

### Choose **Option 4 (WMS-Only)** if:
- You just want hillshade visualization (alternative lighting angles)
- No need for slope/aspect analysis
- Want zero implementation effort

**→ 5 minutes to add**

### Choose **Option 3 Phase 1 (Pre-Computed)** if:
- Want slope & aspect layers for popular areas
- Want to avoid hosting
- Willing to invest 4-6 hours
- Can defer device computation to later (if needed)

**→ Good balance of effort vs. value**

### Choose **Option 2 (Device-Computed)** if:
- Want true offline-first, no external dependencies whatsoever
- Willing to invest 20-30 hours
- Users need slope/aspect for unmapped areas
- Want maximum flexibility

**→ Best alignment with philosophy, most work**

### Choose **Option 1 (Server-Hosted)** if:
- Want tiles distributed via CDN for speed
- Can maintain a server
- Don't mind external hosting dependency

**→ Not recommended for AlpineNav**

---

## Recommendation for AlpineNav

**Start with Option 3 Phase 1 (Pre-Computed):**

1. **Immediate** (~4-6 hours):
   - Compute slope/aspect for Dolomites using Python script
   - Add "Download terrain analysis" UI
   - Test download + display flow

2. **Later** (if users request):
   - Consider Phase 2 (device computation)
   - Evaluate demand vs. effort

**Why Phase 1?**
- ✅ Low effort relative to device computation
- ✅ Gives users immediate value (slope/aspect)
- ✅ No external hosting dependency
- ✅ Tests UX assumptions
- ✅ Can evolve to full device computation if needed

---

## Files to Read

In order of detail:

1. **This file** (TERRAIN_ANALYSIS_OPTIONS.md) — Overview (you're reading it)
2. **[TERRAIN_ANALYSIS_EXPLORATION.md](TERRAIN_ANALYSIS_EXPLORATION.md)** — Detailed comparison of all options
3. **[DEVICE_LOCAL_COMPUTATION.md](DEVICE_LOCAL_COMPUTATION.md)** — Device computation architecture (if considering Option 2/3 Phase 2)
4. **[LIDAR_PROCESSING.md](LIDAR_PROCESSING.md)** — Complete technical reference (if going Option 1)
5. **[SLOPE_ASPECT_QUICKSTART.md](SLOPE_ASPECT_QUICKSTART.md)** — Copy-paste commands for computing

---

## Next Steps (If You Want to Explore)

### Step 1: Decide Which Option
Use the decision guide above. I recommend **Option 3 Phase 1**.

### Step 2: Understand the Details
Read `TERRAIN_ANALYSIS_EXPLORATION.md` to understand trade-offs.

### Step 3: Prototype (Optional)
If interested in Option 3 Phase 1:
- Follow `SLOPE_ASPECT_QUICKSTART.md`
- Compute slope/aspect for a small area (30 min–1 hour)
- Tile to PNG (15 min)
- Create minimal UI to display from local files
- Gauge feasibility and UX

### Step 4: Decision
Do you want to proceed? If so, which option?

---

## Technical Summary Table

| Factor | Option 1 (Server) | Option 2 (Device) | Option 3 (Hybrid) | Option 4 (WMS) |
|--------|-------------------|-------------------|-------------------|----------------|
| **Implementation effort** | 3-4h | 20-30h | 4-6h (Phase 1) | <1h |
| **Hosting required?** | **Yes** | No | No | No |
| **Fully offline?** | ✅ (after download) | ✅ (after compute) | ✅ (after download) | ❌ (needs network) |
| **Slope/Aspect?** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **User control?** | ❌ No | ✅ Yes | ⚠️ Limited | ❌ No |
| **Aligns with philosophy?** | ⚠️ Somewhat | ✅ Excellent | ✅ Excellent | ✅ Excellent |
| **App maintenance** | Low | Medium | Medium | Minimal |
| **Recommended?** | ❌ No | ⚠️ Maybe (Phase 2) | ✅ Yes (Phase 1) | ✅ Yes (now) |

---

## Questions?

- **"How do I compute slope?"** → `SLOPE_ASPECT_QUICKSTART.md`
- **"What's the technical deep dive?"** → `LIDAR_PROCESSING.md`
- **"How does device computation work?"** → `DEVICE_LOCAL_COMPUTATION.md`
- **"Why these options?"** → `TERRAIN_ANALYSIS_EXPLORATION.md`

---

## Summary

**You asked a great question.** The device absolutely can compute slope/aspect locally from downloaded DTM.

**My recommendation**: Start with **Option 3 Phase 1** (pre-computed, no hosting). Low effort, high value, can evolve to device computation later if needed. Perfectly fits AlpineNav's offline-first, minimal-dependency philosophy.

