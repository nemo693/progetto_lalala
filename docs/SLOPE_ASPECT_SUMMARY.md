# Slope & Aspect Processing — What's Available

## Overview

I've prepared a complete workflow for computing and integrating slope and aspect layers from Trentino LiDAR data into AlpineNav. Here's what was created:

### Documents Created

1. **`SLOPE_ASPECT_QUICKSTART.md`** ← **Start here**
   - Step-by-step guide (2-4 hours from start to finish)
   - Minimal technical details, focuses on the fastest path
   - Copy-paste commands included

2. **`LIDAR_PROCESSING.md`** ← Complete technical reference
   - Detailed workflow options
   - Multiple approaches (Python, GDAL CLI, QGIS)
   - GeoServer setup, cloud hosting, offline integration
   - Performance estimates and data quality notes
   - Full Python code examples

3. **`compute_terrain_analysis.py`** ← Automation script
   - Located in `scripts/`
   - Takes DTM GeoTIFF → outputs slope, aspect, TRI, colorized versions
   - Handles the heavy computational work
   - Run: `python scripts/compute_terrain_analysis.py --dtm dtm.tif --output-dir ./output`

---

## The Big Picture

### What You're Computing

From the 1×1 m Trentino LiDAR DTM, you can derive:

| Layer | Use Case | Output | File Size (typical) |
|-------|----------|--------|----------------------|
| **Slope (degrees)** | Avalanche risk, climbing difficulty, terrain classification | 0-90°, colorized RGB | 50-150 MB (tiled) |
| **Aspect (compass)** | Snow accumulation, solar exposure, route planning | 0-360° (8 directions), colorized RGB | 50-150 MB (tiled) |
| **Terrain Ruggedness** | Rock/scree detection, terrain roughness | 0-∞, scalar | 30-80 MB (tiled) |
| **Hillshade** | Visual reference (alternative lighting angles) | Grayscale, 315° or 135° | 40-100 MB (tiled) |

### Slope Color Scheme (for skiing/mountaineering)
- **Green** (<20°): Safe, ski-able
- **Yellow** (20-45°): Moderate, avalanche-prone
- **Red** (>45°): Steep, exposed

### Aspect Color Scheme (compass directions)
- **Red**: North (cold, stable)
- **Blue**: South (sunny, rapid consolidation)
- Plus NE, SE, SW, NW, and E/W variants

---

## Three Deployment Paths

### Path 1: Fastest (Local Testing)
1. Download DTM from STEM portal (1-2 GB)
2. Run `compute_terrain_analysis.py`
3. Tile with `gdal2tiles.py`
4. Serve locally via `python -m http.server 8000`
5. Test in AlpineNav via localhost URL
6. **Time**: 1-2 hours

### Path 2: Free Cloud (GitHub Pages)
1-3. Same as Path 1
4. Push tiles to GitHub Pages
5. Add URL to `map_source.dart`
6. App uses GitHub-hosted tiles
7. **Time**: 2-3 hours, includes git setup
8. **Cost**: Free

### Path 3: Production (CDN)
1-3. Same as Path 1
4. Upload tiles to S3/Azure/CloudFront
5. Set up CDN distribution
6. Add CDN URL to `map_source.dart`
7. **Time**: 3-4 hours
8. **Cost**: ~$0.50-2/month for typical usage

---

## Integration into AlpineNav

Once tiles are computed and hosted, integration is simple. Edit `lib/models/map_source.dart`:

```dart
// Add these constants
static const trentinoSlope = MapSource(
  id: 'trentino_slope',
  name: 'Slope (degrees)',
  type: MapSourceType.rasterXyz,
  url: 'https://your-host.com/tiles/slope/{z}/{x}/{y}.png',
  attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 60000,
);

static const trentinoAspect = MapSource(
  id: 'trentino_aspect',
  name: 'Aspect (compass)',
  type: MapSourceType.rasterXyz,
  url: 'https://your-host.com/tiles/aspect/{z}/{x}/{y}.png',
  attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 60000,
);

// Add to all() list
static const List<MapSource> all = [
  openFreeMap,
  openTopoMap,
  esriWorldImagery,
  trentinoOrthophoto,
  trentinoLidarShading,
  trentinoSlope,        // ← New
  trentinoAspect,       // ← New
];
```

That's it. The layers will automatically appear in the map source picker.

---

## Computing Locally vs. Hosting

### Fully Offline (Pre-computed in App)

You can include tiles as app assets if you want 100% offline support:

```dart
static const trentinoSlope = MapSource(
  id: 'trentino_slope',
  name: 'Slope (offline)',
  type: MapSourceType.rasterXyz,
  url: 'assets/tiles/slope/{z}/{x}/{y}.png',  // ← Local assets
  ...
);
```

**Pros**: Fully offline
**Cons**: Large APK size (~100-200 MB for full Trentino at zoom 10-18)

### Hosted Online (Recommended for Now)

```dart
url: 'https://cdn.myserver.com/tiles/slope/{z}/{x}/{y}.png',
```

**Pros**: Smaller app, easier updates, CDN distribution
**Cons**: Requires internet for layer viewing (cached tiles can still be downloaded)

You can support **both**: users can download slope/aspect tiles on demand using the existing offline download UI in AlpineNav.

---

## Performance & Storage

| Scale | DTM Size | Slope Tiles (z10-18) | Aspect Tiles (z10-18) | Time to Compute |
|-------|----------|----------------------|-----------------------|-----------------|
| Single peak (1 km²) | 50 MB | 2 MB | 2 MB | 5 min |
| Valley (10 km²) | 500 MB | 20 MB | 20 MB | 15 min |
| Dolomites (500 km²) | 25 GB | 1 GB | 1 GB | 1-2 hrs |
| Full Trentino (6,200 km²) | 300 GB | 12 GB | 12 GB | 8-12 hrs |

**Recommendation**: Start with a single peak or valley, get the workflow working, then expand.

---

## Commands Cheat Sheet

```bash
# Setup
conda create -n lidar python=3.10 gdal numpy scipy matplotlib rasterio
conda activate lidar
pip install gdal2tiles

# Compute derivatives
python scripts/compute_terrain_analysis.py \
  --dtm /path/to/dtm.tif \
  --output-dir ./terrain_analysis

# Tile for web
gdal2tiles.py -z 10-18 -w none \
  ./terrain_analysis/slope_colorized.tif \
  ./tiles/slope/

# Local server (testing)
cd ./tiles && python -m http.server 8000

# Check tiles
ls tiles/slope/  # Should see 10/x/y.png, 11/x/y.png, etc.
```

---

## Next Steps (Your Decision)

### Option A: Try It Now (Recommended)
1. Read `SLOPE_ASPECT_QUICKSTART.md`
2. Download a small DTM tile from STEM (Dolomites area, ~1-2 GB)
3. Run the script
4. Test locally with `http.server`
5. Add to AlpineNav and see how it looks

### Option B: Host in Production First
1. Read `LIDAR_PROCESSING.md` section "Step 5: Publish as WMS"
2. Set up S3 bucket or GitHub Pages
3. Compute and upload tiles
4. Add permanent URL to AlpineNav

### Option C: Wait for More Context
If you want to discuss:
- Which terrain derivatives are most useful for your users?
- Color schemes (current "skitour" is good for skiing)?
- Cloud vs. local hosting strategy?
- Offline download strategy?

---

## Questions?

Refer to these docs:
- **Quick reference**: `SLOPE_ASPECT_QUICKSTART.md`
- **Technical deep dive**: `LIDAR_PROCESSING.md`
- **Automation**: `scripts/compute_terrain_analysis.py` (includes docstrings)
- **Existing app patterns**: See `lib/services/wms_tile_server.dart` and `lib/models/map_source.dart`

---

## Summary of Approach

**The workflow I've documented allows you to:**

1. ✅ Download high-resolution LiDAR data (1m pixels) from Trentino
2. ✅ Compute standard GIS derivatives (slope, aspect, TRI)
3. ✅ Colorize for visualization (intuitive color schemes for mountain users)
4. ✅ Tile and cache efficiently (reuse existing WMS proxy architecture)
5. ✅ Integrate into AlpineNav with one line of code per layer
6. ✅ Support offline download (fits existing offline manager pattern)

**No new dependencies** — uses existing `rasterio`, `numpy`, and GDAL (which you likely have for GIS work).

**Fits your philosophy** — minimal, functional, information-dense. No animations, just useful terrain analysis tools.
