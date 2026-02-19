# Device-Local Slope & Aspect Computation

## Concept

Instead of hosting pre-computed slope/aspect tiles on a server, the user's device computes them from DTM data that's already been downloaded for offline use.

```
User downloads DTM tiles from Trentino STEM (via existing offline downloader)
                    ↓
            Stored as GeoTIFF locally
                    ↓
        User toggles "Show slope layer"
                    ↓
    Device computes slope from DTM (background task)
                    ↓
        Caches result as PNG tiles locally
                    ↓
        Displays from cache (fully offline)
```

## Why This Works for AlpineNav

1. **DTM already available**: User must download DTM for other offline features (base terrain)
2. **No external hosting required**: Computation happens entirely on device
3. **Fully offline**: After download + computation, works without network
4. **Aligns with philosophy**: No external dependencies, privacy-preserving
5. **User controls parameters**: Can adjust slope thresholds, color schemes, etc.

## How It Would Work

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│ User Device (AlpineNav)                                 │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐     ┌──────────────────────────┐  │
│  │  Downloaded DTM  │────▶│ Native Slope Computation │  │
│  │   GeoTIFFs       │     │  (Kotlin + SIMD)         │  │
│  │  (1-5 GB)        │     │                          │  │
│  └──────────────────┘     │  - Read DTM pixels       │  │
│                           │  - Compute gradients     │  │
│                           │  - Cache PNG tiles       │  │
│                           │  - Report progress       │  │
│                           └──────────────────────────┘  │
│                                     ↓                    │
│                           ┌──────────────────────┐       │
│                           │  Cached PNG Tiles    │       │
│                           │  (100-150 MB/layer)  │       │
│                           └──────────────────────┘       │
│                                     ↓                    │
│                           ┌──────────────────────┐       │
│                           │   MapLibre Display   │       │
│                           │  (Fully offline)     │       │
│                           └──────────────────────┘       │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Phases

#### Phase 1: User Downloads DTM

Uses existing offline downloader (already works):

```dart
// Already implemented in offline_manager.dart
await offlineManager.downloadDtmRegion(
  bounds: dolomitesBounds,
  minZoom: 10,
  maxZoom: 18,
);
```

DTM stored as GeoTIFF tiles: `documents/wms_cache/dtm_315_wg/{z}/{x}/{y}.jpg`

#### Phase 2: User Requests Slope Layer

New UI element:

```dart
// In map_screen.dart, add button to "Download terrain analysis"
FloatingActionButton(
  child: Icon(Icons.terrain),
  onPressed: () => _startSlopeComputation(),
);
```

#### Phase 3: Device Computes Slope

Background task using Kotlin:

```kotlin
// native_slope.kt (new file)
class SlopeComputation {
    fun computeForDtmTile(
        dtmPixels: FloatArray,
        width: Int,
        height: Int,
        outputPath: String  // Where to save PNG
    ): Boolean {
        // Zevenbergen-Thorne gradient
        val slope = FloatArray(width * height)
        for (i in 1 until height - 1) {
            for (j in 1 until width - 1) {
                val center = dtmPixels[i * width + j]
                val e = dtmPixels[i * width + (j + 1)]
                val w = dtmPixels[i * width + (j - 1)]
                val n = dtmPixels[(i - 1) * width + j]
                val s = dtmPixels[(i + 1) * width + j]

                val dX = (e - w) / 2.0f
                val dY = (n - s) / 2.0f
                slope[i * width + j] = atan(sqrt(dX * dX + dY * dY))
            }
        }

        // Colorize (green/yellow/red for ski touring)
        val rgb = colorizeSlope(slope, width, height)

        // Write PNG
        return writePng(rgb, width, height, outputPath)
    }
}
```

Called from Dart:

```dart
// lib/services/terrain_analysis_service.dart (new file)
class TerrainAnalysisService {
    static const platform = MethodChannel('com.alpineav/terrain');

    Future<void> computeSlope({
        required String dtmDirectory,
        required String outputDirectory,
        required Function(double progress) onProgress,
    }) async {
        try {
            await platform.invokeMethod('computeSlope', {
                'dtmDir': dtmDirectory,
                'outputDir': outputDirectory,
            });
        } catch (e) {
            debugPrint('Slope computation error: $e');
        }
    }
}
```

#### Phase 4: Cache & Display

Slope tiles cached locally:

```
documents/terrain_analysis/slope/{z}/{x}/{y}.png
```

Add to `map_source.dart`:

```dart
static const trentinoSlopeLocal = MapSource(
  id: 'trentino_slope_computed',
  name: 'Slope (computed)',
  type: MapSourceType.rasterXyz,
  url: 'file://{docsDir}/terrain_analysis/slope/{z}/{x}/{y}.png',
  attribution: '© Computed from Trentino LiDAR DTM',
  tileSize: 256,
  avgTileSizeBytes: 100000,
);
```

Display via MapLibre (already works):

```dart
// map_screen.dart
mapController.setStyle(source.styleString);  // Shows slope layer
```

## Performance Estimates

### Computation Time (Per Tile)

| Implementation | Time per 512×512 tile | Time for 50 tiles |
|---|---|---|
| **Pure Kotlin (CPU)** | ~50ms | 2.5 sec |
| **Kotlin + SIMD (NEON)** | ~10ms | 0.5 sec |

**Target**: SIMD version (~10ms per tile) for snappy UX.

### Battery Impact

- **Computation time**: 5 minutes continuous CPU
- **Battery drain**: ~5-10% (acceptable for optional feature)

### Device Storage

| Component | Size |
|---|---|
| DTM for typical region (50 km²) | ~500 MB |
| Slope tiles (after computation) | ~100-150 MB |
| Aspect tiles (after computation) | ~100-150 MB |
| **Total** | ~700-800 MB |

Fits comfortably on modern Android devices (typical 64-128 GB storage).

## Implementation Roadmap

### Tier 1: Prototype (4-6 hours)
- [ ] Implement basic Kotlin slope computation (simple CPU, no SIMD)
- [ ] Test on one DTM tile
- [ ] Save as PNG locally
- [ ] Verify display in MapLibre
- **Deliverable**: Proof-of-concept; shows it's feasible

### Tier 2: Production Quality (15-20 hours)
- [ ] SIMD optimization (NEON on ARM)
- [ ] Multi-threaded computation for multiple tiles
- [ ] Progress UI (progress bar, estimated time remaining)
- [ ] Error handling (disk space, corrupted DTM, etc.)
- [ ] Aspect computation (compass-colored)
- [ ] Terrain Ruggedness Index (TRI)
- [ ] Caching & invalidation logic
- **Deliverable**: Feature ready for Phase 5

### Tier 3: User Polish (10-15 hours)
- [ ] Settings UI: slope thresholds, color schemes
- [ ] Manual re-computation with different params
- [ ] Storage management: clear cached tiles
- [ ] Documentation & UX help text
- **Deliverable**: Production-ready feature

---

## Code Structure

### New Files to Create

```
lib/
  services/
    terrain_analysis_service.dart     # Dart interface to native code
  models/
    terrain_layer.dart                # TerrainLayer model (similar to MapSource)

android/
  app/src/main/
    kotlin/com/alpineav/
      TerrainAnalysisChannel.kt       # Method channel handler
      SlopeComputation.kt             # Slope algorithm
      AspectComputation.kt            # Aspect algorithm
      TerrainRasterizer.kt            # PNG writing

android/
  app/src/main/cpp/
    terrain.cpp                       # SIMD-optimized C++ (optional, Phase 2)
```

### Example: TerrainAnalysisService.dart

```dart
import 'package:flutter/services.dart';

class TerrainAnalysisService {
  static const platform = MethodChannel('com.alpineav/terrain');

  /// Compute slope from DTM tiles and cache as PNG.
  ///
  /// Reads from [dtmDirectory], writes to [outputDirectory].
  /// Calls [onProgress] with values 0.0-1.0 during computation.
  static Future<void> computeSlope({
    required String dtmDirectory,
    required String outputDirectory,
    required Function(double progress) onProgress,
    int minZoom = 10,
    int maxZoom = 18,
  }) async {
    try {
      final stream = await platform.invokeListMethod<double>('computeSlope', {
        'dtmDir': dtmDirectory,
        'outputDir': outputDirectory,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
      });

      stream?.forEach(onProgress);
    } on PlatformException catch (e) {
      throw 'Slope computation failed: ${e.message}';
    }
  }

  /// Similar for aspect, TRI, etc.
  static Future<void> computeAspect({
    required String dtmDirectory,
    required String outputDirectory,
    required Function(double progress) onProgress,
  }) => /* ... */ null;
}
```

### Example: TerrainAnalysisChannel.kt

```kotlin
package com.alpineav

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class TerrainAnalysisChannel(private val activity: Activity) {
    companion object {
        const val CHANNEL = "com.alpineav/terrain"
    }

    fun setupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "computeSlope" -> {
                    val dtmDir = call.argument<String>("dtmDir")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    val minZoom = call.argument<Int>("minZoom") ?: 10
                    val maxZoom = call.argument<Int>("maxZoom") ?: 18

                    val computation = SlopeComputation(dtmDir, outputDir)
                    computation.compute(minZoom, maxZoom) { progress ->
                        // Send progress back to Dart
                        result.success(progress)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
```

---

## Comparison: Pre-Computed vs. Device-Computed

| Aspect | Pre-Computed (Option 1) | Device-Computed (Option 2) |
|--------|------------------------|--------------------------|
| **You host?** | Yes (S3, CDN) | No |
| **Computation time** | One-time offline | Per user, on device (~30s) |
| **Download size** | ~150 MB per layer | DTM already downloaded (~500 MB) |
| **First load** | 5-30 min download | 30-60 sec computation |
| **Offline** | ✅ After download | ✅ After computation |
| **Implementation** | 3-4 hours | 20-30 hours |
| **Maintenance** | Monitor server | Occasional bug fixes |

## Hybrid Approach (Recommended)

**Start with pre-computed** (Option 1, ~4 hours):
- Compute for popular areas (Dolomites, Brenta)
- Include in GitHub release
- Low effort, gives users immediate value
- Proven UX

**Add device-computation as Phase 5** (~20-30 hours):
- Users can compute slope/aspect for unmapped areas
- For power users / advanced features
- Only if demand justifies effort

---

## Risks & Mitigations

### Risk: Computation is slow (worse UX than pre-computed)
**Mitigation**: Use SIMD optimizations, multi-threading; aim for <30 sec per region

### Risk: Battery drain
**Mitigation**: Only compute when user requests; show battery impact warning

### Risk: Device storage fills up
**Mitigation**: Clear old cache; warn user before computation if low space

### Risk: DTM tiles corrupted
**Mitigation**: Validate DTM file format; graceful error if corrupt

### Risk: Mid-range Android devices struggle
**Mitigation**: Profile on Redmi 14; use Kotlin/SIMD for performance

---

## Decision: Should AlpineNav Do This?

### If Yes:
- Strong alignment with offline-first philosophy
- Users get full control over computation
- No hosting maintenance burden
- Good long-term flexibility

### If No:
- Pre-computed tiles (Option 1) sufficient for Phase 4.5
- Simpler initial implementation
- Can add device computation later if users request

**Recommendation**: Start with pre-computed (trivial), evaluate demand before investing in device computation.

