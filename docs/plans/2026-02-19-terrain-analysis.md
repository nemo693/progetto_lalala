# Terrain Analysis (Slope & Aspect) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users select an area on the map, download elevation data (AWS Terrarium tiles), compute slope and aspect on-device in pure Dart, and display the result as a standalone map layer.

**Architecture:** Fetch Terrarium-encoded PNGs from AWS S3 (`elevation-tiles-prod`), decode RGB to elevation, compute slope/aspect per tile using 3x3 Zevenbergen-Thorne kernel, colorize to PNG, cache locally, display via `file://` raster XYZ source in MapLibre. All pure Dart, no native code.

**Tech Stack:** Flutter/Dart, `http` (already in pubspec), `dart:ui` for PNG encode/decode, existing `tile_calculator.dart` for bbox/tile math, existing `WmsTileServer` cache pattern for storage.

---

## Important Context

### Flutter command (spaces in path)
```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" <command>
```

### AWS Terrarium tile format
- URL: `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`
- Encoding: `elevation_m = (R * 256 + G + B / 256) - 32768`
- 256x256 PNG tiles, zoom 0-15, free, no API key
- EPSG:3857 (Web Mercator) — same as existing tile math

### Existing patterns to reuse
- `lib/utils/tile_calculator.dart` — `enumerateTileCoords()`, `BoundingBox`, `TileCoord`, `formatBytes()`
- `lib/services/wms_tile_server.dart` — cache dir pattern (`${appDir}/wms_cache/`), tile fetch with retries
- `lib/models/map_source.dart` — `MapSource`, `_buildRasterStyleJson()` pattern, `rasterXyz` type
- `lib/widgets/download_progress_overlay.dart` — progress stream pattern
- `lib/screens/map_screen.dart` — download bottom sheet pattern, source picker

### Key design decisions
- **Standalone layer** (replaces base map, not overlay) — keeps existing MapSource switching simple
- **Single zoom level** for computation — compute at z12 (covers ~10km x 10km per tile, ~30m resolution). MapLibre over-zooms gracefully for higher zooms.
- **Hillshade blended into slope colors** — so the standalone layer is legible without a base map underneath
- **Computation in Dart isolate** — keeps UI responsive during slope math
- **Cache structure**: `${appDir}/terrain_analysis/{layer}/{z}/{x}/{y}.png`

---

## Task 1: Terrarium Tile Decoder (Pure Logic)

**Files:**
- Create: `lib/services/terrain_service.dart`
- Test: `test/terrain_service_test.dart`

This task implements the core math: decode Terrarium PNG bytes to elevation grid, compute slope, compute aspect, colorize. No I/O, no Flutter dependencies — pure functions that take bytes in and return bytes out.

**Step 1: Write failing tests for Terrarium decoding**

```dart
// test/terrain_service_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/terrain_service.dart';

void main() {
  group('TerrainService.decodeTerrarium', () {
    test('decodes known RGB values to elevation', () {
      // Terrarium: elevation = (R * 256 + G + B / 256) - 32768
      // For sea level (0m): R=128, G=0, B=0 -> (128*256 + 0 + 0) - 32768 = 0
      expect(TerrainService.terrariumToElevation(128, 0, 0), closeTo(0.0, 0.1));

      // For 1000m: (R*256 + G + B/256) = 33768
      // R = 33768 ~/ 256 = 131, G = 33768 % 256 = 232, B = 0
      // elevation = (131*256 + 232 + 0) - 32768 = 33768 - 32768 = 1000
      expect(TerrainService.terrariumToElevation(131, 232, 0), closeTo(1000.0, 0.5));

      // For 3000m: 35768 -> R=139, G=184, B=0
      expect(TerrainService.terrariumToElevation(139, 184, 0), closeTo(3000.0, 0.5));
    });

    test('decodes RGBA bytes to elevation grid', () {
      // 2x2 grid of pixels, all at sea level (R=128, G=0, B=0, A=255)
      final rgba = Uint8List.fromList([
        128, 0, 0, 255, 128, 0, 0, 255,
        128, 0, 0, 255, 128, 0, 0, 255,
      ]);
      final grid = TerrainService.decodeTerrarium(rgba, 2, 2);
      expect(grid.length, 4); // 2x2
      expect(grid[0], closeTo(0.0, 0.1));
      expect(grid[3], closeTo(0.0, 0.1));
    });
  });

  group('TerrainService.computeSlope', () {
    test('returns zero slope for flat terrain', () {
      // 3x3 grid, all at 1000m
      final elevation = Float64List.fromList([
        1000, 1000, 1000,
        1000, 1000, 1000,
        1000, 1000, 1000,
      ]);
      final slope = TerrainService.computeSlope(elevation, 3, 3, cellSize: 30.0);
      // Center pixel should be 0 degrees
      expect(slope[4], closeTo(0.0, 0.1));
    });

    test('computes non-zero slope for tilted terrain', () {
      // 3x3 grid with 30m cell size, rising 30m east-to-west
      // That's a 45-degree slope in the E-W direction
      final elevation = Float64List.fromList([
        1030, 1030, 1030,
        1030, 1030, 1030,
        1030, 1030, 1030,
      ]);
      // Actually let's make it slope east: left=low, right=high
      elevation[0] = 1000; elevation[1] = 1000; elevation[2] = 1000;
      elevation[3] = 1015; elevation[4] = 1015; elevation[5] = 1015;
      elevation[6] = 1030; elevation[7] = 1030; elevation[8] = 1030;

      final slope = TerrainService.computeSlope(elevation, 3, 3, cellSize: 30.0);
      // Center pixel: south-north gradient = (1000-1030)/(2*30) = -0.5
      // arctan(0.5) ~ 26.6 degrees
      expect(slope[4], greaterThan(20.0));
      expect(slope[4], lessThan(30.0));
    });
  });

  group('TerrainService.computeAspect', () {
    test('returns -1 for flat terrain', () {
      final elevation = Float64List.fromList([
        1000, 1000, 1000,
        1000, 1000, 1000,
        1000, 1000, 1000,
      ]);
      final aspect = TerrainService.computeAspect(elevation, 3, 3, cellSize: 30.0);
      expect(aspect[4], -1.0); // flat = no aspect
    });

    test('detects north-facing slope', () {
      // Higher in south, lower in north -> north-facing
      final elevation = Float64List.fromList([
        900,  900,  900,
        950,  950,  950,
        1000, 1000, 1000,
      ]);
      final aspect = TerrainService.computeAspect(elevation, 3, 3, cellSize: 30.0);
      // North-facing should be ~0 or ~360 degrees
      expect(aspect[4], anyOf(lessThan(45.0), greaterThan(315.0)));
    });
  });

  group('TerrainService.colorizeSlope', () {
    test('returns RGBA bytes of correct length', () {
      final slope = Float64List.fromList([0, 15, 30, 45]);
      final hillshade = Float64List.fromList([200, 150, 100, 50]);
      final rgba = TerrainService.colorizeSlope(slope, hillshade, 2, 2);
      expect(rgba.length, 2 * 2 * 4); // width * height * RGBA
    });

    test('gentle slope produces greenish pixels', () {
      final slope = Float64List.fromList([5, 5, 5, 5]);
      final hillshade = Float64List.fromList([200, 200, 200, 200]);
      final rgba = TerrainService.colorizeSlope(slope, hillshade, 2, 2);
      // First pixel: R, G, B, A
      // Green channel should dominate for gentle slopes
      expect(rgba[1], greaterThan(rgba[0])); // G > R
    });
  });

  group('TerrainService.computeHillshade', () {
    test('returns values in 0-255 range', () {
      final elevation = Float64List.fromList([
        1000, 1010, 1020,
        1000, 1010, 1020,
        1000, 1010, 1020,
      ]);
      final hs = TerrainService.computeHillshade(elevation, 3, 3, cellSize: 30.0);
      for (final v in hs) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(255));
      }
    });
  });
}
```

**Step 2: Run test to verify it fails**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test test/terrain_service_test.dart
```
Expected: FAIL — `terrain_service.dart` doesn't exist yet.

**Step 3: Implement TerrainService**

```dart
// lib/services/terrain_service.dart
import 'dart:math';
import 'dart:typed_data';

/// Pure computation functions for terrain analysis.
///
/// Decodes AWS Terrarium elevation tiles, computes slope/aspect/hillshade,
/// and colorizes results. All functions are pure (no I/O, no Flutter deps)
/// so they can run in isolates.
class TerrainService {
  // ── Terrarium decoding ──────────────────────────────────────────

  /// Decode a single Terrarium pixel to elevation in meters.
  ///
  /// Terrarium encoding: elevation = (R * 256 + G + B / 256) - 32768
  static double terrariumToElevation(int r, int g, int b) {
    return (r * 256.0 + g + b / 256.0) - 32768.0;
  }

  /// Decode RGBA pixel bytes into a flat elevation grid (row-major).
  ///
  /// [rgba] contains 4 bytes per pixel: R, G, B, A.
  /// Returns a Float64List of length [width] * [height].
  static Float64List decodeTerrarium(Uint8List rgba, int width, int height) {
    final grid = Float64List(width * height);
    for (int i = 0; i < width * height; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      grid[i] = terrariumToElevation(r, g, b);
    }
    return grid;
  }

  // ── Slope computation ───────────────────────────────────────────

  /// Compute slope in degrees for each pixel using Horn's method.
  ///
  /// [elevation] is a flat grid of [width] x [height] elevations.
  /// [cellSize] is the ground distance per pixel in meters.
  /// Edge pixels are set to 0.
  ///
  /// Returns Float64List of slope in degrees (0-90).
  static Float64List computeSlope(
    Float64List elevation,
    int width,
    int height, {
    required double cellSize,
  }) {
    final slope = Float64List(width * height);

    for (int row = 1; row < height - 1; row++) {
      for (int col = 1; col < width - 1; col++) {
        final idx = row * width + col;

        // 3x3 neighborhood
        final nw = elevation[(row - 1) * width + (col - 1)];
        final n  = elevation[(row - 1) * width + col];
        final ne = elevation[(row - 1) * width + (col + 1)];
        final w  = elevation[row * width + (col - 1)];
        final e  = elevation[row * width + (col + 1)];
        final sw = elevation[(row + 1) * width + (col - 1)];
        final s  = elevation[(row + 1) * width + col];
        final se = elevation[(row + 1) * width + (col + 1)];

        // Horn's method (same as GDAL gdaldem slope)
        final dzdx = ((ne + 2 * e + se) - (nw + 2 * w + sw)) / (8 * cellSize);
        final dzdy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) / (8 * cellSize);

        slope[idx] = atan(sqrt(dzdx * dzdx + dzdy * dzdy)) * 180.0 / pi;
      }
    }

    return slope;
  }

  // ── Aspect computation ──────────────────────────────────────────

  /// Compute aspect in degrees (0=N, 90=E, 180=S, 270=W, -1=flat).
  ///
  /// Same neighborhood and gradient as slope.
  static Float64List computeAspect(
    Float64List elevation,
    int width,
    int height, {
    required double cellSize,
    double flatThreshold = 1.0,
  }) {
    final aspect = Float64List(width * height);
    // Initialize to -1 (flat)
    for (int i = 0; i < aspect.length; i++) {
      aspect[i] = -1.0;
    }

    for (int row = 1; row < height - 1; row++) {
      for (int col = 1; col < width - 1; col++) {
        final idx = row * width + col;

        final nw = elevation[(row - 1) * width + (col - 1)];
        final n  = elevation[(row - 1) * width + col];
        final ne = elevation[(row - 1) * width + (col + 1)];
        final w  = elevation[row * width + (col - 1)];
        final e  = elevation[row * width + (col + 1)];
        final sw = elevation[(row + 1) * width + (col - 1)];
        final s  = elevation[(row + 1) * width + col];
        final se = elevation[(row + 1) * width + (col + 1)];

        final dzdx = ((ne + 2 * e + se) - (nw + 2 * w + sw)) / (8 * cellSize);
        final dzdy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) / (8 * cellSize);

        final slopeRad = atan(sqrt(dzdx * dzdx + dzdy * dzdy));
        final slopeDeg = slopeRad * 180.0 / pi;

        if (slopeDeg < flatThreshold) {
          aspect[idx] = -1.0;
          continue;
        }

        // atan2(-dzdy, -dzdx) gives angle from north, clockwise
        var a = atan2(-dzdy, -dzdx) * 180.0 / pi;
        // Convert from math angles to compass: north=0, east=90
        a = (a + 360) % 360;
        aspect[idx] = a;
      }
    }

    return aspect;
  }

  // ── Hillshade ───────────────────────────────────────────────────

  /// Compute hillshade illumination (0-255).
  ///
  /// Default: azimuth 315 (NW), altitude 45 degrees — standard cartographic
  /// lighting. Used to blend with slope/aspect colors for legibility.
  static Float64List computeHillshade(
    Float64List elevation,
    int width,
    int height, {
    required double cellSize,
    double azimuthDeg = 315.0,
    double altitudeDeg = 45.0,
  }) {
    final hs = Float64List(width * height);

    final azRad = azimuthDeg * pi / 180.0;
    final altRad = altitudeDeg * pi / 180.0;

    for (int row = 1; row < height - 1; row++) {
      for (int col = 1; col < width - 1; col++) {
        final idx = row * width + col;

        final nw = elevation[(row - 1) * width + (col - 1)];
        final n  = elevation[(row - 1) * width + col];
        final ne = elevation[(row - 1) * width + (col + 1)];
        final w  = elevation[row * width + (col - 1)];
        final e  = elevation[row * width + (col + 1)];
        final sw = elevation[(row + 1) * width + (col - 1)];
        final s  = elevation[(row + 1) * width + col];
        final se = elevation[(row + 1) * width + (col + 1)];

        final dzdx = ((ne + 2 * e + se) - (nw + 2 * w + sw)) / (8 * cellSize);
        final dzdy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) / (8 * cellSize);

        final slopeRad = atan(sqrt(dzdx * dzdx + dzdy * dzdy));
        final aspectRad = atan2(-dzdy, -dzdx);

        // Standard hillshade formula
        var illumination = sin(altRad) * cos(slopeRad) +
            cos(altRad) * sin(slopeRad) * cos(azRad - aspectRad);

        hs[idx] = (illumination.clamp(0.0, 1.0) * 255.0);
      }
    }

    // Edge pixels: neutral gray
    for (int col = 0; col < width; col++) {
      hs[col] = 180.0; // top row
      hs[(height - 1) * width + col] = 180.0; // bottom row
    }
    for (int row = 0; row < height; row++) {
      hs[row * width] = 180.0; // left col
      hs[row * width + (width - 1)] = 180.0; // right col
    }

    return hs;
  }

  // ── Colorization ────────────────────────────────────────────────

  /// Colorize slope with ski-touring color scheme, blended with hillshade.
  ///
  /// Color bins (degrees):
  ///   0-27: green (safe touring terrain)
  ///   27-30: yellow (critical avalanche angle)
  ///   30-35: orange (very steep, high avalanche risk)
  ///   35-45: red (extreme)
  ///   45+: dark red (cliff/rock)
  ///
  /// Returns RGBA Uint8List of length width*height*4.
  static Uint8List colorizeSlope(
    Float64List slope,
    Float64List hillshade,
    int width,
    int height, {
    double hillshadeBlend = 0.35,
  }) {
    final rgba = Uint8List(width * height * 4);

    for (int i = 0; i < width * height; i++) {
      final s = slope[i];
      final hs = hillshade[i] / 255.0; // normalize to 0-1

      // Base color from slope bins
      int r, g, b;
      if (s < 27) {
        // Green — safe ski touring
        r = 76; g = 175; b = 80;
      } else if (s < 30) {
        // Yellow — critical 27-30 degree band
        r = 255; g = 235; b = 59;
      } else if (s < 35) {
        // Orange — steep, high risk
        r = 255; g = 152; b = 0;
      } else if (s < 45) {
        // Red — extreme
        r = 244; g = 67; b = 54;
      } else {
        // Dark red — cliff/rock
        r = 139; g = 0; b = 0;
      }

      // Blend with hillshade for terrain relief visibility
      final blend = 1.0 - hillshadeBlend + hillshadeBlend * hs;
      rgba[i * 4]     = (r * blend).round().clamp(0, 255);
      rgba[i * 4 + 1] = (g * blend).round().clamp(0, 255);
      rgba[i * 4 + 2] = (b * blend).round().clamp(0, 255);
      rgba[i * 4 + 3] = 255; // fully opaque
    }

    return rgba;
  }

  /// Colorize aspect with 8-direction compass, blended with hillshade.
  ///
  /// N=red, NE=orange, E=yellow, SE=green, S=cyan, SW=blue, W=purple, NW=pink.
  /// Flat areas (aspect=-1) shown as neutral gray.
  ///
  /// Returns RGBA Uint8List of length width*height*4.
  static Uint8List colorizeAspect(
    Float64List aspect,
    Float64List hillshade,
    int width,
    int height, {
    double hillshadeBlend = 0.35,
  }) {
    final rgba = Uint8List(width * height * 4);

    for (int i = 0; i < width * height; i++) {
      final a = aspect[i];
      final hs = hillshade[i] / 255.0;

      int r, g, b;
      if (a < 0) {
        // Flat — gray
        r = 160; g = 160; b = 160;
      } else if (a < 22.5 || a >= 337.5) {
        // N — red (cold, shady in Alps)
        r = 215; g = 48; b = 39;
      } else if (a < 67.5) {
        // NE — orange
        r = 252; g = 141; b = 89;
      } else if (a < 112.5) {
        // E — yellow
        r = 254; g = 224; b = 144;
      } else if (a < 157.5) {
        // SE — light green
        r = 145; g = 207; b = 96;
      } else if (a < 202.5) {
        // S — green (sunny in Alps)
        r = 26; g = 152; b = 80;
      } else if (a < 247.5) {
        // SW — teal
        r = 0; g = 176; b = 185;
      } else if (a < 292.5) {
        // W — blue
        r = 69; g = 117; b = 180;
      } else {
        // NW — purple
        r = 145; g = 80; b = 180;
      }

      final blend = 1.0 - hillshadeBlend + hillshadeBlend * hs;
      rgba[i * 4]     = (r * blend).round().clamp(0, 255);
      rgba[i * 4 + 1] = (g * blend).round().clamp(0, 255);
      rgba[i * 4 + 2] = (b * blend).round().clamp(0, 255);
      rgba[i * 4 + 3] = 255;
    }

    return rgba;
  }

  // ── Cell size calculation ───────────────────────────────────────

  /// Approximate ground resolution (meters/pixel) for a Terrarium tile.
  ///
  /// At the equator, zoom 0 = ~156km/pixel. At zoom 12 in the Alps (~46N),
  /// one 256px tile covers ~6.7km, so cellSize ~ 26m.
  static double cellSizeMeters(int zoom, double latitudeDeg) {
    const earthCircumference = 40075016.686; // meters
    final metersPerPixel =
        earthCircumference * cos(latitudeDeg * pi / 180.0) / (256 * (1 << zoom));
    return metersPerPixel;
  }
}
```

**Step 4: Run tests**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test test/terrain_service_test.dart
```
Expected: ALL PASS.

**Step 5: Commit**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && git add lib/services/terrain_service.dart test/terrain_service_test.dart && git commit -m "feat: add terrain analysis core — Terrarium decode, slope, aspect, hillshade, colorize"
```

---

## Task 2: Terrain Tile Manager (Download + Compute + Cache)

**Files:**
- Create: `lib/services/terrain_tile_manager.dart`
- Test: `test/terrain_tile_manager_test.dart`

This task handles the full pipeline: enumerate tiles for an area, download Terrarium PNGs from AWS, decode elevation, compute slope/aspect, encode result as PNG, cache to disk. Reports progress via a stream.

**Step 1: Write failing tests**

```dart
// test/terrain_tile_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/terrain_tile_manager.dart';
import 'package:alpinenav/utils/tile_calculator.dart';

void main() {
  group('TerrainTileManager', () {
    test('terrariumUrl builds correct URL', () {
      final url = TerrainTileManager.terrariumUrl(12, 2176, 1456);
      expect(url, 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/2176/1456.png');
    });

    test('outputPath builds correct cache path', () {
      final path = TerrainTileManager.outputPath('/cache', 'slope', 12, 2176, 1456);
      expect(path, '/cache/terrain_analysis/slope/12/2176/1456.png');
    });

    test('estimateTerrainTiles returns correct count for single zoom', () {
      const bbox = BoundingBox(
        minLat: 46.5, minLon: 11.3, maxLat: 46.6, maxLon: 11.4,
      );
      final tiles = TerrainTileManager.enumerateTerrainTiles(bbox, zoom: 12);
      expect(tiles, isNotEmpty);
      // All tiles should be at zoom 12
      for (final t in tiles) {
        expect(t.z, 12);
      }
    });

    test('TerrainProgress reports fields correctly', () {
      const p = TerrainProgress(
        phase: TerrainPhase.downloading,
        current: 5,
        total: 20,
        layer: 'slope',
      );
      expect(p.fraction, closeTo(0.25, 0.01));
      expect(p.isComplete, false);
    });

    test('TerrainProgress isComplete when current == total and phase is done', () {
      const p = TerrainProgress(
        phase: TerrainPhase.done,
        current: 20,
        total: 20,
        layer: 'slope',
      );
      expect(p.isComplete, true);
    });
  });
}
```

**Step 2: Run test to verify it fails**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test test/terrain_tile_manager_test.dart
```
Expected: FAIL.

**Step 3: Implement TerrainTileManager**

```dart
// lib/services/terrain_tile_manager.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/tile_calculator.dart';
import 'terrain_service.dart';

/// Progress phases for terrain computation.
enum TerrainPhase { downloading, computing, done, error }

/// Progress report for terrain analysis.
class TerrainProgress {
  final TerrainPhase phase;
  final int current;
  final int total;
  final String layer; // 'slope' or 'aspect'
  final String? error;

  const TerrainProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.layer,
    this.error,
  });

  double get fraction => total > 0 ? current / total : 0.0;
  bool get isComplete => phase == TerrainPhase.done;
}

/// Manages terrain analysis tile lifecycle: download, compute, cache.
///
/// Downloads AWS Terrarium elevation tiles, computes slope or aspect
/// using [TerrainService], caches colorized PNG results to disk.
class TerrainTileManager {
  static const _terrariumBase =
      'https://s3.amazonaws.com/elevation-tiles-prod/terrarium';

  /// Build the Terrarium tile URL.
  static String terrariumUrl(int z, int x, int y) => '$_terrariumBase/$z/$x/$y.png';

  /// Build the output cache path for a computed tile.
  static String outputPath(String cacheDir, String layer, int z, int x, int y) =>
      '$cacheDir/terrain_analysis/$layer/$z/$x/$y.png';

  /// Enumerate terrain tiles for a bounding box at a single zoom level.
  static List<TileCoord> enumerateTerrainTiles(BoundingBox bbox, {int zoom = 12}) {
    return enumerateTileCoords(bbox: bbox, minZoom: zoom, maxZoom: zoom);
  }

  /// Check if a computed terrain tile exists in the cache.
  static Future<bool> isCached(String cacheDir, String layer, int z, int x, int y) async {
    final file = File(outputPath(cacheDir, layer, z, x, y));
    return file.exists();
  }

  /// Get the base cache directory.
  static Future<String> getCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  /// Compute terrain analysis for a bounding box.
  ///
  /// Downloads Terrarium tiles, computes [layer] ('slope' or 'aspect'),
  /// saves colorized PNG tiles to cache. Yields [TerrainProgress] updates.
  ///
  /// Tiles are computed at [zoom] level (default 12, ~26m resolution in Alps).
  /// Set [skipCached] to true to skip tiles already computed.
  static Stream<TerrainProgress> computeForArea({
    required BoundingBox bbox,
    required String layer, // 'slope' or 'aspect'
    int zoom = 12,
    bool skipCached = true,
  }) async* {
    final cacheDir = await getCacheDir();
    final tiles = enumerateTerrainTiles(bbox, zoom: zoom);
    final total = tiles.length;

    if (total == 0) {
      yield TerrainProgress(
          phase: TerrainPhase.done, current: 0, total: 0, layer: layer);
      return;
    }

    // Phase 1: Download Terrarium tiles (with neighbor padding)
    yield TerrainProgress(
        phase: TerrainPhase.downloading, current: 0, total: total, layer: layer);

    // We need a 1-tile border around each tile for the 3x3 kernel.
    // Collect all tiles + neighbors, deduplicate.
    final allNeeded = <TileCoord>{};
    for (final t in tiles) {
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          allNeeded.add(TileCoord(t.x + dx, t.y + dy, t.z));
        }
      }
    }

    // Download all needed Terrarium tiles
    final elevationCache = <TileCoord, Float64List>{};
    int downloaded = 0;
    for (final t in allNeeded) {
      try {
        final bytes = await _downloadTerrariumTile(t.z, t.x, t.y);
        if (bytes != null) {
          final rgba = await _decodePng(bytes);
          if (rgba != null) {
            elevationCache[t] = TerrainService.decodeTerrarium(rgba, 256, 256);
          }
        }
      } catch (e) {
        debugPrint('[TerrainTileManager] Failed to download ${t.z}/${t.x}/${t.y}: $e');
      }
      downloaded++;
      if (downloaded % 5 == 0 || downloaded == allNeeded.length) {
        yield TerrainProgress(
          phase: TerrainPhase.downloading,
          current: (downloaded * total / allNeeded.length).round().clamp(0, total),
          total: total,
          layer: layer,
        );
      }
    }

    // Phase 2: Compute slope/aspect for each target tile
    yield TerrainProgress(
        phase: TerrainPhase.computing, current: 0, total: total, layer: layer);

    int computed = 0;
    for (final t in tiles) {
      // Check cache
      if (skipCached && await isCached(cacheDir, layer, t.z, t.x, t.y)) {
        computed++;
        continue;
      }

      // Build a 258x258 elevation grid: the 256x256 tile + 1px border from neighbors
      // For simplicity in v1: just process each tile individually (loses 1px border accuracy)
      // TODO(terrain): stitch neighbor tiles for accurate edge pixels
      final elev = elevationCache[t];
      if (elev == null) {
        computed++;
        continue; // No data for this tile
      }

      final cellSize = TerrainService.cellSizeMeters(t.z, _tileCenterLat(t));

      final hillshade = TerrainService.computeHillshade(
          elev, 256, 256, cellSize: cellSize);

      Uint8List rgba;
      if (layer == 'slope') {
        final slope = TerrainService.computeSlope(elev, 256, 256, cellSize: cellSize);
        rgba = TerrainService.colorizeSlope(slope, hillshade, 256, 256);
      } else {
        final aspect = TerrainService.computeAspect(elev, 256, 256, cellSize: cellSize);
        rgba = TerrainService.colorizeAspect(aspect, hillshade, 256, 256);
      }

      // Encode as PNG and save
      await _savePng(rgba, 256, 256, outputPath(cacheDir, layer, t.z, t.x, t.y));

      computed++;
      if (computed % 3 == 0 || computed == total) {
        yield TerrainProgress(
          phase: TerrainPhase.computing,
          current: computed,
          total: total,
          layer: layer,
        );
      }
    }

    yield TerrainProgress(
        phase: TerrainPhase.done, current: total, total: total, layer: layer);
  }

  /// Delete all cached terrain analysis tiles.
  static Future<void> clearCache() async {
    final cacheDir = await getCacheDir();
    final dir = Directory('$cacheDir/terrain_analysis');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      debugPrint('[TerrainTileManager] cleared terrain cache');
    }
  }

  /// Delete cached tiles for a specific layer.
  static Future<void> clearLayerCache(String layer) async {
    final cacheDir = await getCacheDir();
    final dir = Directory('$cacheDir/terrain_analysis/$layer');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Get cache size for terrain analysis tiles.
  static Future<int> getCacheSize() async {
    final cacheDir = await getCacheDir();
    final dir = Directory('$cacheDir/terrain_analysis');
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  // ── Private helpers ─────────────────────────────────────────────

  static double _tileCenterLat(TileCoord t) {
    final north = tileYToLat(t.y, t.z);
    final south = tileYToLat(t.y + 1, t.z);
    return (north + south) / 2.0;
  }

  static Future<Uint8List?> _downloadTerrariumTile(int z, int x, int y) async {
    final url = terrariumUrl(z, x, y);
    const maxRetries = 3;
    const retryDelays = [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)];

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } on TimeoutException {
        debugPrint('[TerrainTileManager] Timeout $z/$x/$y (attempt ${attempt + 1})');
      } catch (e) {
        debugPrint('[TerrainTileManager] Error $z/$x/$y (attempt ${attempt + 1}): $e');
      }
      if (attempt < maxRetries - 1) {
        await Future.delayed(retryDelays[attempt]);
      }
    }
    return null;
  }

  /// Decode PNG bytes to RGBA pixel data using dart:ui.
  static Future<Uint8List?> _decodePng(Uint8List pngBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[TerrainTileManager] PNG decode error: $e');
      return null;
    }
  }

  /// Encode RGBA pixels as PNG and save to disk.
  static Future<void> _savePng(
      Uint8List rgba, int width, int height, String path) async {
    try {
      // Use dart:ui to encode
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba, width, height, ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );
      final image = await completer.future;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData != null) {
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      }
    } catch (e) {
      debugPrint('[TerrainTileManager] PNG encode/save error: $e');
    }
  }
}
```

**Step 4: Run tests**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test test/terrain_tile_manager_test.dart
```
Expected: ALL PASS (only testing pure URL/path/progress logic, not I/O).

**Step 5: Commit**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && git add lib/services/terrain_tile_manager.dart test/terrain_tile_manager_test.dart && git commit -m "feat: add terrain tile manager — download, compute, cache pipeline"
```

---

## Task 3: MapSource Entries for Terrain Layers

**Files:**
- Modify: `lib/models/map_source.dart`
- Modify: `test/map_source_test.dart`

Add `slopeAnalysis` and `aspectAnalysis` as built-in MapSource entries that read from the local terrain cache via `file://` URLs. These are `rasterXyz` type with a special flag indicating they need computation before display.

**Step 1: Write failing test**

Add to `test/map_source_test.dart`:

```dart
group('Terrain analysis sources', () {
  test('slopeAnalysis is rasterXyz type', () {
    expect(MapSource.slopeAnalysis.type, MapSourceType.rasterXyz);
  });

  test('aspectAnalysis is rasterXyz type', () {
    expect(MapSource.aspectAnalysis.type, MapSourceType.rasterXyz);
  });

  test('slopeAnalysis has terrain_analysis in id', () {
    expect(MapSource.slopeAnalysis.id, contains('slope'));
  });

  test('terrain sources are in all list', () {
    expect(MapSource.all.contains(MapSource.slopeAnalysis), true);
    expect(MapSource.all.contains(MapSource.aspectAnalysis), true);
  });

  test('terrain sources need computation flag', () {
    expect(MapSource.slopeAnalysis.needsComputation, true);
    expect(MapSource.aspectAnalysis.needsComputation, true);
    expect(MapSource.openFreeMap.needsComputation, false);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test test/map_source_test.dart
```

**Step 3: Implement changes to MapSource**

In `lib/models/map_source.dart`:

1. Add `needsComputation` field and `terrainLayer` field to `MapSource`:

```dart
/// Whether this source requires on-device computation before display.
/// Terrain analysis sources need to download DTM and compute slope/aspect.
final bool needsComputation;

/// For terrain sources: which layer to compute ('slope' or 'aspect').
final String? terrainLayer;
```

2. Update the constructor to include the new fields (with defaults `false` and `null`).

3. Add the two built-in terrain sources:

```dart
static const slopeAnalysis = MapSource(
  id: 'terrain_slope',
  name: 'Slope Analysis',
  type: MapSourceType.rasterXyz,
  url: '', // Set dynamically from cache dir at runtime
  attribution: 'Elevation: AWS Terrain Tiles (Mapzen/USGS)',
  tileSize: 256,
  avgTileSizeBytes: 15000, // compressed colorized PNG
  needsComputation: true,
  terrainLayer: 'slope',
);

static const aspectAnalysis = MapSource(
  id: 'terrain_aspect',
  name: 'Aspect Analysis',
  type: MapSourceType.rasterXyz,
  url: '', // Set dynamically from cache dir at runtime
  attribution: 'Elevation: AWS Terrain Tiles (Mapzen/USGS)',
  tileSize: 256,
  avgTileSizeBytes: 15000,
  needsComputation: true,
  terrainLayer: 'aspect',
);
```

4. Add them to the `all` list.

5. Add a method to build the style string from a cache dir:

```dart
/// Build style string for terrain sources, pointing at local file cache.
String terrainStyleString(String cacheDir) {
  assert(needsComputation);
  final tileUrl = 'file://$cacheDir/terrain_analysis/$terrainLayer/{z}/{x}/{y}.png';
  final escapedAttribution = attribution.replaceAll('"', '\\"');
  return '{'
      '"version":8,'
      '"name":"$name",'
      '"sources":{'
      '"raster-tiles":{'
      '"type":"raster",'
      '"tiles":["$tileUrl"],'
      '"tileSize":$tileSize,'
      '"maxzoom":22,'
      '"attribution":"$escapedAttribution"'
      '}'
      '},'
      '"layers":[{'
      '"id":"raster-layer",'
      '"type":"raster",'
      '"source":"raster-tiles",'
      '"minzoom":0,'
      '"maxzoom":22'
      '}]'
      '}';
}
```

**Step 4: Run all tests**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test
```
Expected: ALL PASS (including existing tests).

**Step 5: Commit**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && git add lib/models/map_source.dart test/map_source_test.dart && git commit -m "feat: add slope and aspect MapSource entries with terrain style builder"
```

---

## Task 4: UI Integration — Map Screen

**Files:**
- Modify: `lib/screens/map_screen.dart`

Integrate terrain analysis into the existing map screen:
1. When user selects a terrain source, check if tiles exist for the visible area
2. If not, show a bottom sheet offering to compute
3. Show progress during download+compute
4. Once done, switch to the terrain style

**Step 1: Add terrain computation trigger to map_screen.dart**

When the user selects `slopeAnalysis` or `aspectAnalysis` from the source picker, instead of directly switching the style, check if computed tiles exist for the visible area. If not, show a confirmation dialog, then start computation.

Key additions to `_MapScreenState`:

```dart
// Add import at top:
import '../services/terrain_tile_manager.dart';

// In the source switching logic (where _selectedSource is set):
// After setting _selectedSource, check if it needs computation:

Future<void> _handleTerrainSource(MapSource source) async {
  // Get visible bounds from map camera
  final bounds = await _mapProvider?.getVisibleBounds();
  if (bounds == null) return;

  final bbox = BoundingBox(
    minLat: bounds.south,
    minLon: bounds.west,
    maxLat: bounds.north,
    maxLon: bounds.east,
  );

  final cacheDir = await TerrainTileManager.getCacheDir();
  final tiles = TerrainTileManager.enumerateTerrainTiles(bbox);

  // Check if all tiles are cached
  bool allCached = true;
  for (final t in tiles) {
    if (!await TerrainTileManager.isCached(
        cacheDir, source.terrainLayer!, t.z, t.x, t.y)) {
      allCached = false;
      break;
    }
  }

  if (allCached) {
    // Tiles exist — switch directly
    _applyTerrainStyle(source, cacheDir);
    return;
  }

  // Show computation dialog
  final shouldCompute = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      title: Text('Compute ${source.name}?',
          style: const TextStyle(color: Colors.white)),
      content: Text(
          'This will download elevation data and compute '
          '${source.terrainLayer} for the visible area '
          '(${tiles.length} tiles). Requires internet.',
          style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Compute'),
        ),
      ],
    ),
  );

  if (shouldCompute != true || !mounted) return;

  // Start computation with progress
  _startTerrainComputation(source, bbox, cacheDir);
}

void _startTerrainComputation(MapSource source, BoundingBox bbox, String cacheDir) {
  final stream = TerrainTileManager.computeForArea(
    bbox: bbox,
    layer: source.terrainLayer!,
  );

  setState(() {
    _terrainProgressStream = stream.asBroadcastStream();
    _isComputingTerrain = true;
  });

  _terrainProgressStream!.listen(
    (progress) {
      if (progress.isComplete && mounted) {
        setState(() => _isComputingTerrain = false);
        _applyTerrainStyle(source, cacheDir);
      }
    },
    onError: (e) {
      if (mounted) {
        setState(() => _isComputingTerrain = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terrain computation failed: $e')),
        );
      }
    },
  );
}

void _applyTerrainStyle(MapSource source, String cacheDir) {
  final style = source.terrainStyleString(cacheDir);
  _mapController?.setStyle(style);
  setState(() {
    _selectedSource = source;
  });
}
```

**Step 2: Add terrain progress overlay**

Reuse the existing `DownloadProgressOverlay` pattern. In the `Stack` children of the `build` method, add:

```dart
if (_isComputingTerrain && _terrainProgressStream != null)
  _buildTerrainProgressOverlay(),
```

Where `_buildTerrainProgressOverlay` returns a simple overlay widget showing the phase (downloading/computing) and progress.

**Step 3: Run analyze**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" analyze
```
Expected: 0 issues.

**Step 4: Run all tests**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test
```
Expected: ALL PASS.

**Step 5: Commit**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && git add lib/screens/map_screen.dart && git commit -m "feat: integrate terrain analysis into map screen — compute dialog, progress, style switch"
```

---

## Task 5: Verify Full Pipeline

**Step 1: Run full test suite**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" test
```

**Step 2: Run analyze**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" analyze
```

**Step 3: Build debug APK**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && "C:/Users/Emilio Dorigatti/flutter/bin/flutter.bat" build apk --debug
```

**Step 4: Device testing checklist**

Test on Redmi 14:
- [ ] Open layer picker, see "Slope Analysis" and "Aspect Analysis" in list
- [ ] Select "Slope Analysis" — confirmation dialog appears
- [ ] Tap "Compute" — progress overlay shows downloading phase
- [ ] Progress transitions to computing phase
- [ ] On completion, map shows colorized slope tiles
- [ ] Zoom in — MapLibre over-zooms gracefully (no black tiles)
- [ ] Pan to new area — tiles outside computed area show empty
- [ ] Re-select "Slope Analysis" in same area — switches instantly (cached)
- [ ] Switch to different source (OpenFreeMap) and back — slope tiles still display
- [ ] Select "Aspect Analysis" — new computation for aspect layer
- [ ] Kill app and restart — cached tiles still display without recompute

**Step 5: Final commit + push**

```bash
cd "C:/Users/Emilio Dorigatti/progetto_lalala" && git add -A && git commit -m "feat: terrain analysis complete — slope & aspect from AWS elevation tiles" && git push
```

---

## Summary

| Task | What | New files | Estimated time |
|------|------|-----------|---------------|
| 1 | Core math (decode, slope, aspect, hillshade, colorize) | `terrain_service.dart` + test | 2-3h |
| 2 | Download + compute + cache pipeline | `terrain_tile_manager.dart` + test | 3-4h |
| 3 | MapSource entries + terrain style builder | modify `map_source.dart` + test | 1h |
| 4 | Map screen integration (dialog, progress, style switch) | modify `map_screen.dart` | 3-4h |
| 5 | Full pipeline verification + device test | - | 2-3h |
| **Total** | | **2 new files, 2 modified** | **~12-15h** |

### Architecture diagram
```
User taps "Slope Analysis" in layer picker
        |
        v
map_screen.dart: check cache for visible area
        |
   [not cached]──────────────────[cached]
        |                            |
        v                            v
  Confirm dialog              Apply file:// style
        |                     (instant display)
        v
TerrainTileManager.computeForArea()
        |
        ├── Download Terrarium PNGs from AWS S3
        |   (https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png)
        |
        ├── Decode RGB → elevation (TerrainService.decodeTerrarium)
        |
        ├── Compute slope + hillshade (TerrainService)
        |
        ├── Colorize (ski-touring scheme blended with hillshade)
        |
        └── Save PNG → ${appDir}/terrain_analysis/slope/{z}/{x}/{y}.png
                |
                v
        Apply file:// style to MapLibre
        (terrain_analysis/slope/{z}/{x}/{y}.png)
```
