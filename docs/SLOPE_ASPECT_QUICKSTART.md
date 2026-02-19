# Quick Start: Adding Slope & Aspect Layers to AlpineNav

## TL;DR

You want slope and aspect visualization in AlpineNav. Here's the fastest path:

```
1. Download DTM GeoTIFF from STEM (Trentino LiDAR)
2. Compute slope/aspect with our Python script
3. Tile to XYZ format
4. Host on a server (or include in app as offline tiles)
5. Add to map_source.dart as rasterXyz source
```

**Time estimate**: 2-4 hours (including GIS software setup)

---

## Step-by-Step Quick Path

### Step 1: Get GDAL + Python tools

**Windows (via conda, recommended)**
```bash
conda create -n lidar python=3.10 gdal numpy scipy matplotlib rasterio
conda activate lidar
pip install gdal2tiles  # for XYZ tiling
```

**Mac (Homebrew)**
```bash
brew install gdal
pip install --user rasterio numpy scipy gdal2tiles
```

**Linux (Ubuntu/Debian)**
```bash
sudo apt-get install gdal-bin python3-gdal gdal-data
pip3 install rasterio numpy scipy gdal2tiles
```

### Step 2: Download DTM from STEM

1. Go to https://siat.provincia.tn.it/stem/
2. Zoom to your area of interest (or select entire Trentino)
3. Click "Download" → Select **DTM** → Choose **GeoTIFF** format
4. Download (file will be ~500 MB–2 GB depending on area)

**Example**: Downloading Dolomites area takes ~5 min

### Step 3: Compute Slope & Aspect

```bash
cd /path/to/progetto_lalala

# Activate conda env
conda activate lidar

# Run the computation script
python scripts/compute_terrain_analysis.py \
  --dtm /path/to/dtm_download.tif \
  --output-dir ./temp/terrain_analysis

# Output files:
# - slope_degrees.tif (raw 32-bit float)
# - slope_colorized.tif (RGB, green→yellow→red)
# - aspect_degrees.tif (raw 32-bit float)
# - aspect_colorized.tif (RGB, compass colors)
```

**Time**: ~5-15 min depending on DTM size

### Step 4: Tile to XYZ Format

```bash
# Tile slope for zoom 10-18
gdal2tiles.py -z 10-18 -w none \
  ./temp/terrain_analysis/slope_colorized.tif \
  ./tiles/slope_webmerc/

# Tile aspect
gdal2tiles.py -z 10-18 -w none \
  ./temp/terrain_analysis/aspect_colorized.tif \
  ./tiles/aspect_webmerc/

# Output: tiles/slope_webmerc/{z}/{x}/{y}.png
#         tiles/aspect_webmerc/{z}/{x}/{y}.png
```

**Time**: ~10-20 min

### Step 5: Host the Tiles

**Option A: Local HTTP Server (Testing)**
```bash
cd ./tiles
python3 -m http.server 8000
# Tiles now at http://localhost:8000/slope_webmerc/{z}/{x}/{y}.png
```

**Option B: GitHub Pages (Free, Static)**
1. Create gh-pages branch
2. Push tiles/ to GitHub
3. Enable Pages in repo settings
4. Tiles at: `https://username.github.io/repo/slope_webmerc/{z}/{x}/{y}.png`

**Option C: S3 + CloudFront (Production)**
1. Upload tiles to S3 bucket
2. Set CloudFront distribution
3. Tiles at: `https://cdn.myserver.com/tiles/slope/{z}/{x}/{y}.png`

### Step 6: Add to AlpineNav

Edit `lib/models/map_source.dart`:

```dart
static const trentinoSlope = MapSource(
  id: 'trentino_slope',
  name: 'Slope (degrees)',
  type: MapSourceType.rasterXyz,
  url: 'https://cdn.example.com/tiles/slope_webmerc/{z}/{x}/{y}.png',
  attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 60000,
);

static const trentinoAspect = MapSource(
  id: 'trentino_aspect',
  name: 'Aspect (cardinal)',
  type: MapSourceType.rasterXyz,
  url: 'https://cdn.example.com/tiles/aspect_webmerc/{z}/{x}/{y}.png',
  attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 60000,
);

static const List<MapSource> all = [
  openFreeMap,
  openTopoMap,
  esriWorldImagery,
  trentinoOrthophoto,
  trentinoLidarShading,
  trentinoSlope,       // ← Add this
  trentinoAspect,      // ← Add this
];
```

Then rebuild:
```bash
flutter run --release
```

---

## What Each Visualization Shows

### Slope
- **Green** (<20°): Gentle terrain, safe for skiing/climbing
- **Yellow** (20-45°): Moderate angle, requires technique, avalanche-prone
- **Red** (>45°): Steep, exposed rock, exposed cornices

**Use case**: Route planning, avalanche risk assessment, terrain difficulty

### Aspect (Compass Directions)
- **Red**: North — cold, holds snow longer, good for late-season skiing
- **Yellow**: NE — variable exposure
- **Green**: East — gets morning sun, slopes often consolidate
- **Cyan**: SE — good visibility, afternoon shade
- **Blue**: South — maximum sun exposure, may be icy or bare
- **Magenta**: SW — maximum sun, rapid consolidation
- **White**: West — afternoon sun
- **Orange**: NW — cold/shaded
- **Gray**: Flat terrain (no meaningful aspect)

**Use case**: Snow stability prediction, thermal routing, solar route planning

---

## Common Issues & Fixes

### "GDAL not found"
```bash
# Install system GDAL first
# Ubuntu: sudo apt-get install libgdal-dev
# Mac: brew install gdal
# Then reinstall pip packages
pip install --upgrade --force-reinstall gdal rasterio
```

### "gdal2tiles.py not found"
```bash
pip install gdal2tiles
# Or run directly:
python -m gdal2tiles --version
```

### Tiles are huge (~100+ MB)
- Use compression: `gdal2tiles.py -co COMPRESS=DEFLATE ...`
- Reduce tile zoom range: `gdal2tiles.py -z 12-17` (skip 10-11)
- Pre-optimize with COG: `gdal_translate -of COG input.tif output.tif`

### Tiles don't align with map
- Verify CRS is Web Mercator (EPSG:3857)
- Check tile folder structure: should be `z/x/y.png` exactly
- Use gdal2tiles with `-w none` flag to disable attribution

---

## What if I Want to Skip Tiling?

You can also serve raw GeoTIFFs as COG (Cloud Optimized GeoTIFF) directly:

```bash
# Convert to COG
gdal_translate -of COG -co COMPRESS=DEFLATE slope_colorized.tif slope_cog.tif

# Host on S3, then add to AlpineNav as:
static const trentinoSlope = MapSource(
  id: 'trentino_slope',
  name: 'Slope',
  type: MapSourceType.rasterXyz,
  url: 'https://s3.amazonaws.com/mybucket/slope_cog.tif/{z}/{x}/{y}',
  // ... (requires special URL format or proxy)
);
```

**Note**: Most web map libraries expect XYZ tile URL patterns, not raw GeoTIFFs. Stick with tiling for compatibility.

---

## Next: Offline Download Support

Once tiles are hosted, you can add offline download support:

```dart
// In offline_manager.dart
Future<void> downloadSlope({
  required LatLngBounds bounds,
  required int minZoom = 10,
  required int maxZoom = 18,
}) async {
  final tiles = calculateTilesInBounds(bounds, minZoom, maxZoom);

  for (final tile in tiles) {
    final url = 'https://cdn.example.com/tiles/slope_webmerc/'
        '${tile.z}/${tile.x}/${tile.y}.png';
    await _downloadTile(url, 'trentino_slope', tile);
  }
}
```

---

## Full Reference

See `LIDAR_PROCESSING.md` for complete technical details, alternative workflows, and advanced options.

---

## Support

- **Trentino STEM Portal**: https://siat.provincia.tn.it/stem/
- **GDAL Docs**: https://gdal.org/
- **Rasterio Docs**: https://rasterio.readthedocs.io/
- **AlpineNav Docs**: See `docs/` folder in this repo
