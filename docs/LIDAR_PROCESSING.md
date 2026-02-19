# LiDAR Slope, Aspect & Terrain Analysis — Processing Guide

## Overview

This guide explains how to download LiDAR DTM data from Trentino, compute derived products (slope, aspect, curvature, roughness), and serve them as WMS layers in AlpineNav.

The Trentino LiDAR dataset (2014/2018 integrated) provides high-resolution Digital Terrain Model (DTM) at 1×1 m resolution across the entire province. From this, you can compute standard terrain analysis products for mountaineering, ski touring, and backcountry navigation.

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Download DTM GeoTIFF from STEM portal                   │
│    (https://siat.provincia.tn.it/stem/)                    │
└─────────────────────────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼──────────────────┐
                    │ 2. Compute derivatives with GDAL  │
                    │    - Slope (% or degrees)         │
                    │    - Aspect (0-360°)              │
                    │    - Hillshade (for reference)    │
                    │    - Roughness / TRI / TPI        │
                    └─────────────────┬──────────────────┘
                                      │
                    ┌─────────────────▼──────────────────┐
                    │ 3. Tile and colorize (optional)   │
                    │    - Tile to COG (Cloud Optimized │
                    │      GeoTIFF)                      │
                    │    - Apply color ramps             │
                    └─────────────────┬──────────────────┘
                                      │
        ┌─────────────────────────────▼──────────────────────┐
        │ 4. Publish as WMS or raster tiles                 │
        │    Option A: GeoServer (self-hosted on device?)   │
        │    Option B: Cloud-hosted WMS (AWS, Azure)        │
        │    Option C: Pre-tiled XYZ (rasterXyz in app)     │
        └─────────────────────────────────────────────────────┘
```

---

## Step 1: Download DTM Data from STEM Portal

### Manual Download (via GUI)

1. Visit **https://siat.provincia.tn.it/stem/**
2. Select your area of interest (or download by tile)
3. Choose **DTM** (Digital Terrain Model)
4. Select format: **GeoTIFF** (recommended for processing)
5. Download the file(s)

### Programmatic Download (via REST API)

The STEM portal provides data in blocks of ~2×2 km. You can automate downloads using Python:

```bash
# Example: download DTM for a specific tile covering the Dolomites
# You'll need to know the tile grid system first (ask STEM support)
```

Alternatively, use the WCS (Web Coverage Service) endpoint if available:

```bash
# WCS GetCoverage request (if supported)
curl "https://siat.provincia.tn.it/geoserver/stem/wcs?
  service=WCS&version=2.0.1&request=GetCoverage
  &coverageId=dtm_1m
  &format=image/tiff
  &SUBSET=x(1234000,1236000)&SUBSET=y(5900000,5902000)" \
  -o dtm_subset.tif
```

**Note**: Contact STEM (Servizio Territorio Ambiente) at [info@siat.provincia.tn.it] to confirm WCS endpoint and available coverage IDs.

---

## Step 2: Compute Terrain Derivatives with GDAL/QGIS

### Option A: QGIS GUI (Easy, Interactive)

1. **Open QGIS**
2. Load the DTM GeoTIFF: `Layer → Add Raster Layer`
3. **Compute Slope**:
   - `Raster → Analysis → Slope`
   - Output CRS: same as input (EPSG:32632 or EPSG:3857)
   - Output units: degrees or %slope
   - Save as `slope.tif`

4. **Compute Aspect**:
   - `Raster → Analysis → Aspect`
   - Output range: 0–360° (N=0°, E=90°, S=180°, W=270°)
   - Save as `aspect.tif`

5. **Compute Hillshade** (optional, for visual reference):
   - `Raster → Analysis → Hillshade`
   - Azimuth: 315° (standard NW lighting)
   - Altitude: 45°
   - Save as `hillshade.tif`

6. **Compute Terrain Roughness Index (TRI)**:
   - `Raster → Analysis → Terrain Ruggedness Index`
   - Save as `tri.tif`

7. **Compute Topographic Position Index (TPI)**:
   - `Raster → Analysis → Topographic Position Index`
   - Save as `tpi.tif`

### Option B: Command-Line (GDAL, Reproducible)

Install GDAL:
```bash
# Ubuntu/Debian
sudo apt-get install gdal-bin gdal-data

# macOS (Homebrew)
brew install gdal

# Windows (conda recommended)
conda install gdal
```

#### Slope
```bash
gdaldem slope dtm.tif slope_degrees.tif -of GTiff -s 1.0
# Options:
#   -s 1.0   : ratio of vertical to horizontal units (1.0 = same units)
#   -alg ZevenbergenThorne : alternative algorithm (more accurate on steep terrain)
gdaldem slope dtm.tif slope_degrees.tif -of GTiff -alg ZevenbergenThorne
```

#### Aspect
```bash
gdaldem aspect dtm.tif aspect.tif -of GTiff
# Output: 0° = North, 90° = East, 180° = South, 270° = West
# Flat areas (-9999 by convention) can be filtered out later
```

#### Hillshade (for reference/visualization)
```bash
gdaldem hillshade dtm.tif hillshade_315.tif -of GTiff -z 1.0 -s 1.0 -az 315 -alt 45
# -az 315  : azimuth (315° = NW)
# -alt 45  : altitude angle above horizon
```

#### Terrain Ruggedness Index (TRI)
```bash
# Not directly in gdaldem; use gdal_translate + gdaldem as workaround, or use QGIS
# TRI = mean absolute difference in elevation between a cell and its 8 neighbors
# Formula: sqrt( sum((elevation[center] - elevation[neighbor])^2) / 8 )
# Use QGIS or custom Python with rasterio for this
```

### Option C: Python Script (Most Flexible)

Use `rasterio` + `numpy` + `scipy` for custom processing:

```python
import numpy as np
import rasterio
from rasterio.plot import show
from scipy.ndimage import convolve

def load_dtm(tif_path):
    """Load DTM as numpy array."""
    with rasterio.open(tif_path) as src:
        dtm = src.read(1).astype(float)
        profile = src.profile
    return dtm, profile

def compute_slope(dtm, cellsize=1.0):
    """
    Compute slope in degrees using Zevenbergen-Thorne method.
    cellsize: DEM resolution in map units (1.0 for 1m LiDAR)
    """
    # Convolution kernels for X and Y gradients
    kernel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=float) / (8 * cellsize)
    kernel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=float) / (8 * cellsize)

    grad_x = convolve(dtm, kernel_x, mode='constant', cval=np.nan)
    grad_y = convolve(dtm, kernel_y, mode='constant', cval=np.nan)

    slope_rad = np.arctan(np.sqrt(grad_x**2 + grad_y**2))
    slope_deg = np.degrees(slope_rad)

    return slope_deg

def compute_aspect(dtm, cellsize=1.0):
    """
    Compute aspect in degrees (0° = N, 90° = E, 180° = S, 270° = W).
    """
    kernel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=float) / (8 * cellsize)
    kernel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=float) / (8 * cellsize)

    grad_x = convolve(dtm, kernel_x, mode='constant', cval=np.nan)
    grad_y = convolve(dtm, kernel_y, mode='constant', cval=np.nan)

    aspect_rad = np.arctan2(grad_y, -grad_x)  # Note: -grad_x for correct compass orientation
    aspect_deg = np.degrees(aspect_rad)
    aspect_deg = (aspect_deg + 360) % 360  # Normalize to 0-360

    return aspect_deg

def compute_tri(dtm):
    """
    Terrain Ruggedness Index: sqrt( sum(dh^2) / 8 )
    where dh = elevation difference between center cell and each of 8 neighbors.
    """
    tri = np.zeros_like(dtm, dtype=float)
    for i in range(1, dtm.shape[0] - 1):
        for j in range(1, dtm.shape[1] - 1):
            center = dtm[i, j]
            neighbors = dtm[i-1:i+2, j-1:j+2].flatten()
            diffs = (center - neighbors) ** 2
            tri[i, j] = np.sqrt(np.mean(diffs))
    return tri

def save_raster(array, profile, output_path, nodata=np.nan):
    """Save numpy array as GeoTIFF."""
    profile.update(dtype=rasterio.float32, count=1, nodata=nodata)
    with rasterio.open(output_path, 'w', **profile) as dst:
        dst.write(array.astype(rasterio.float32), 1)
    print(f"Saved: {output_path}")

# Main workflow
if __name__ == "__main__":
    dtm_path = "dtm_trentino.tif"

    dtm, profile = load_dtm(dtm_path)

    # Compute derivatives
    slope = compute_slope(dtm, cellsize=1.0)
    aspect = compute_aspect(dtm, cellsize=1.0)
    tri = compute_tri(dtm)

    # Save outputs
    save_raster(slope, profile, "slope_degrees.tif", nodata=-9999)
    save_raster(aspect, profile, "aspect_degrees.tif", nodata=-9999)
    save_raster(tri, profile, "tri.tif", nodata=-9999)
```

---

## Step 3: Colorize and Tile for Web Display (Optional but Recommended)

### Colorizing Slope

```python
import numpy as np
import rasterio
from matplotlib.colors import Normalize
import matplotlib.pyplot as plt

def colorize_slope(slope_array, output_path, algorithm='skitour'):
    """
    Colorize slope raster:
    - 'skitour': green (<20°) → yellow (20-45°) → red (>45°)
    - 'climbing': blue (<20°) → green (20-35°) → yellow (35-50°) → red (>50°)
    """

    if algorithm == 'skitour':
        # Ski touring color scheme
        bins = [0, 20, 45, 90]  # Degree thresholds
        colors_rgb = [
            (0, 200, 0),      # Green: safe, gentle
            (255, 255, 0),    # Yellow: moderate, requires technique
            (255, 0, 0),      # Red: steep, avalanche/rockfall risk
        ]
    elif algorithm == 'climbing':
        # Rock climbing color scheme
        bins = [0, 20, 35, 50, 90]
        colors_rgb = [
            (0, 0, 255),      # Blue: walk
            (0, 255, 0),      # Green: easy scramble
            (255, 255, 0),    # Yellow: moderate climbing
            (255, 0, 0),      # Red: hard climbing / exposure
        ]

    # Create RGB output
    h, w = slope_array.shape
    rgb = np.zeros((3, h, w), dtype=np.uint8)

    # Assign colors based on slope value
    for i, (lower, upper) in enumerate(zip(bins[:-1], bins[1:])):
        mask = (slope_array >= lower) & (slope_array < upper)
        rgb[0, mask] = colors_rgb[i][0]  # R
        rgb[1, mask] = colors_rgb[i][1]  # G
        rgb[2, mask] = colors_rgb[i][2]  # B

    # Save as GeoTIFF
    with rasterio.open(output_path, 'w',
                       driver='GTiff',
                       height=h, width=w, count=3,
                       dtype=rasterio.uint8,
                       crs='EPSG:32632',  # UTM 32N (Trentino)
                       transform=src_transform) as dst:
        dst.write(rgb)

    print(f"Saved colorized slope: {output_path}")
```

### Creating Cloud Optimized GeoTIFFs (COG)

```bash
# Convert to COG for fast web tiling
gdal_translate -of COG \
  -co COMPRESS=DEFLATE \
  -co ZLEVEL=9 \
  -co BIGTIFF=IF_SAFER \
  slope_degrees.tif slope_degrees_cog.tif

# COG benefits:
# - Tiled internally (512x512 or 1024x1024 blocks)
# - Reduced file size (compression)
# - Efficient HTTP range requests (no need to download whole file)
```

### Tiling to Web Mercator XYZ

```bash
# Use gdal2tiles.py to create XYZ tile pyramid
gdal2tiles.py -z 10-18 -w none \
  slope_degrees_cog.tif \
  tiles/slope_webmerc/

# Output: tiles/slope_webmerc/{z}/{x}/{y}.png
# Can be served via HTTP or included in app as offline tiles
```

---

## Step 4: Publish as WMS or Integrate into AlpineNav

### Option A: Pre-compute & Include as Offline Raster Tiles

**Pros**: Fast, no server dependency, fully offline
**Cons**: Requires pre-downloading at app build time; larger app size

1. Tile slope/aspect to XYZ at zoom 10-18:
   ```bash
   gdal2tiles.py -z 10-18 slope_degrees_cog.tif tiles/slope/
   ```

2. Add to AlpineNav as rasterXyz source:
   ```dart
   static const trentinoSlope = MapSource(
     id: 'trentino_slope',
     name: 'Trentino Slope (degrees)',
     type: MapSourceType.rasterXyz,
     url: 'file://{appDocDir}/terrain_tiles/slope/{z}/{x}/{y}.png',
     // Or use HTTP endpoint if hosted:
     // url: 'https://myserver.com/tiles/slope/{z}/{x}/{y}.png',
     attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
     tileSize: 256,
     avgTileSizeBytes: 60000,  // Typical colorized PNG
   );
   ```

3. Add to `MapSource.all` list

### Option B: Host on GeoServer (Self-Hosted)

**Pros**: Dynamic, updates without recompiling app
**Cons**: Requires server infrastructure; not fully offline

1. **Install GeoServer locally or on a server**:
   ```bash
   # Docker (recommended)
   docker run -d -p 8080:8080 -e GEOSERVER_ADMIN_USER=admin \
     -e GEOSERVER_ADMIN_PASSWORD=geoserver \
     geosolutionsit/geoserver:latest
   ```

2. **Upload slope/aspect COGs to GeoServer**:
   - Access http://localhost:8080/geoserver/web/
   - Create new workspace: `alpineav`
   - Create new layer: upload `slope_degrees_cog.tif`
   - Create new layer: upload `aspect_cog.tif`

3. **Create WMS GetCapabilities**:
   - WMS endpoint: `http://myserver.com:8080/geoserver/wms`

4. **Add to AlpineNav**:
   ```dart
   static const trentinoSlope = MapSource(
     id: 'trentino_slope_wms',
     name: 'Trentino Slope (WMS)',
     type: MapSourceType.wms,
     url: '',
     wmsBaseUrl: 'http://myserver.com:8080/geoserver/wms',
     wmsLayers: 'alpineav:slope',
     wmsCrs: 'EPSG:3857',
     wmsFormat: 'image/png',
     attribution: '© Provincia Autonoma di Trento',
     tileSize: 512,
     avgTileSizeBytes: 150000,
   );
   ```

### Option C: Cloud-Hosted WMS (AWS/Azure/Mapbox)

**Pros**: Scalable, automatic failover, globally distributed
**Cons**: Cost, external dependency

1. **Upload COG to AWS S3**
2. **Use AWS API Gateway + Lambda** to serve WMS
3. Or use **Mapbox** directly (pre-tiled, built-in)

---

## Step 5: Integrate into AlpineNav (Code Changes)

### 1. Add to `map_source.dart`

```dart
static const trentinoSlope = MapSource(
  id: 'trentino_slope',
  name: 'Slope (degrees)',  // Short name for UI
  type: MapSourceType.rasterXyz,
  url: 'https://myserver.com/tiles/slope/{z}/{x}/{y}.png',
  attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 60000,
);

static const trentinoAspect = MapSource(
  id: 'trentino_aspect',
  name: 'Aspect (0-360°)',  // Cardinal directions
  type: MapSourceType.rasterXyz,
  url: 'https://myserver.com/tiles/aspect/{z}/{x}/{y}.png',
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
  trentinoSlope,        // Add here
  trentinoAspect,       // Add here
];
```

### 2. Update `wms_sources_screen.dart`

The slope/aspect layers will automatically appear in the map source picker since they're in `MapSource.all`.

### 3. Optional: Add Opacity Control

For overlay mode (e.g., slope over orthophoto):

```dart
// In map_screen.dart, add a layer opacity slider
Slider(
  label: 'Opacity',
  value: _layerOpacity,
  onChanged: (val) {
    setState(() => _layerOpacity = val);
    _updateMapLayerOpacity(_layerOpacity);
  },
)
```

Then update the style to adjust opacity:

```dart
Future<void> _updateMapLayerOpacity(double opacity) async {
  if (_mapController == null) return;
  try {
    await _mapController!.setLayerProperties('raster-layer', {
      'paint': {'raster-opacity': opacity}
    });
  } catch (e) {
    debugPrint('Error setting opacity: $e');
  }
}
```

---

## Step 6: Offline Download Integration

If you want to allow users to download slope/aspect tiles for offline use (like orthophoto):

### Update `offline_manager.dart`

```dart
// Add slope/aspect to downloadable sources
Future<void> downloadTerrainAnalysis({
  required LatLngBounds bounds,
  required int minZoom,
  required int maxZoom,
  String sourceId = 'trentino_slope',  // or 'trentino_aspect'
}) async {
  // Reuse existing WMS tile download logic
  final tiles = calculateTilesInBounds(bounds, minZoom, maxZoom);

  for (final tile in tiles) {
    final url = 'https://myserver.com/tiles/$sourceId/${tile.z}/${tile.x}/${tile.y}.png';
    await _downloadTile(url, sourceId, tile);
  }
}
```

---

## Performance & Storage Estimates

| Layer | Format | Zoom 10-18 | Size (typical route, 2km buffer) |
|-------|--------|-----------|----------------------------------|
| Slope (colorized PNG) | PNG, LZ4 | 256px tiles | ~40-80 MB (500-1500 tiles) |
| Aspect (colorized PNG) | PNG, LZ4 | 256px tiles | ~40-80 MB |
| DTM (raw GeoTIFF, for analysis) | COG GeoTIFF | full res (1m) | ~50-200 GB (for all Trentino) |

**Recommendation**: Pre-compute slope/aspect at zoom 10-18 and colorize. ~150 MB per layer for Trentino coverage should be acceptable if served efficiently.

---

## Data Quality Notes

- **Trentino LiDAR resolution**: 1×1 m (Type 1 areas, ~80%) and 2×2 m (Type 2-3 areas)
- **Slope accuracy**: ±2-5° for gentle slopes; larger errors on very steep terrain
- **Aspect accuracy**: ±5-10° due to DTM interpolation artifacts
- **Flatness detection**: Flat cells (slope < 1°) often have meaningless aspect; consider masking aspect output in flat areas
- **Artifacts**: Expect local noise in areas with:
  - Dense forest (LiDAR may miss ground)
  - Buildings/infrastructure
  - Steep cliffs (aliasing effects)

---

## References

- GDAL Documentation: https://gdal.org/
- Rasterio (Python): https://rasterio.readthedocs.io/
- QGIS Raster Analysis: https://docs.qgis.org/latest/en/docs/user_manual/
- GeoServer WMS: https://geoserver.org/
- COG Specification: https://www.cogeo.org/
- Trentino STEM Portal: https://siat.provincia.tn.it/stem/

