import 'dart:async';
import 'dart:io';
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
  static String terrariumUrl(int z, int x, int y) =>
      '$_terrariumBase/$z/$x/$y.png';

  /// Build the output cache path for a computed tile.
  static String outputPath(
          String cacheDir, String layer, int z, int x, int y) =>
      '$cacheDir/terrain_analysis/$layer/$z/$x/$y.png';

  /// Enumerate terrain tiles for a bounding box at a single zoom level.
  static List<TileCoord> enumerateTerrainTiles(BoundingBox bbox,
      {int zoom = 12}) {
    return enumerateTileCoords(bbox: bbox, minZoom: zoom, maxZoom: zoom);
  }

  /// Check if a computed terrain tile exists in the cache.
  static Future<bool> isCached(
      String cacheDir, String layer, int z, int x, int y) async {
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
            elevationCache[t] =
                TerrainService.decodeTerrarium(rgba, 256, 256);
          }
        }
      } catch (e) {
        debugPrint(
            '[TerrainTileManager] Failed to download ${t.z}/${t.x}/${t.y}: $e');
      }
      downloaded++;
      if (downloaded % 5 == 0 || downloaded == allNeeded.length) {
        yield TerrainProgress(
          phase: TerrainPhase.downloading,
          current: (downloaded * total / allNeeded.length)
              .round()
              .clamp(0, total),
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

      final hillshade = TerrainService.computeHillshade(elev, 256, 256,
          cellSize: cellSize);

      Uint8List rgba;
      if (layer == 'slope') {
        final slope = TerrainService.computeSlope(elev, 256, 256,
            cellSize: cellSize);
        rgba = TerrainService.colorizeSlope(slope, hillshade, 256, 256);
      } else {
        final aspect = TerrainService.computeAspect(elev, 256, 256,
            cellSize: cellSize);
        rgba = TerrainService.colorizeAspect(aspect, hillshade, 256, 256);
      }

      // Encode as PNG and save
      await _savePng(
          rgba, 256, 256, outputPath(cacheDir, layer, t.z, t.x, t.y));

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

  // -- Private helpers ------------------------------------------------------

  static double _tileCenterLat(TileCoord t) {
    final north = tileYToLat(t.y, t.z);
    final south = tileYToLat(t.y + 1, t.z);
    return (north + south) / 2.0;
  }

  static Future<Uint8List?> _downloadTerrariumTile(int z, int x, int y) async {
    final url = terrariumUrl(z, x, y);
    const maxRetries = 3;
    const retryDelays = [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } on TimeoutException {
        debugPrint(
            '[TerrainTileManager] Timeout $z/$x/$y (attempt ${attempt + 1})');
      } catch (e) {
        debugPrint(
            '[TerrainTileManager] Error $z/$x/$y (attempt ${attempt + 1}): $e');
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
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );
      final image = await completer.future;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
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
