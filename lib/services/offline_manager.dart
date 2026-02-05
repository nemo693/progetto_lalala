import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/tile_calculator.dart';

/// Progress update during tile download.
class DownloadProgress {
  final int tilesDownloaded;
  final int tilesTotal;
  final int bytesDownloaded;
  final int tilesFailed;
  final bool isComplete;
  final String? error;

  const DownloadProgress({
    required this.tilesDownloaded,
    required this.tilesTotal,
    required this.bytesDownloaded,
    this.tilesFailed = 0,
    this.isComplete = false,
    this.error,
  });

  double get progressPercent =>
      tilesTotal > 0 ? tilesDownloaded / tilesTotal : 0.0;

  @override
  String toString() =>
      'DownloadProgress($tilesDownloaded/$tilesTotal, ${formatBytes(bytesDownloaded)})';
}

/// Metadata for an offline region.
class OfflineRegion {
  final String id;
  final String name;
  final BoundingBox bounds;
  final int minZoom;
  final int maxZoom;
  final int tileCount;
  final int sizeBytes;
  final DateTime createdAt;

  const OfflineRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.sizeBytes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minLat': bounds.minLat,
        'minLon': bounds.minLon,
        'maxLat': bounds.maxLat,
        'maxLon': bounds.maxLon,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'tileCount': tileCount,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OfflineRegion.fromJson(Map<String, dynamic> json) => OfflineRegion(
        id: json['id'] as String,
        name: json['name'] as String,
        bounds: BoundingBox(
          minLat: (json['minLat'] as num).toDouble(),
          minLon: (json['minLon'] as num).toDouble(),
          maxLat: (json['maxLat'] as num).toDouble(),
          maxLon: (json['maxLon'] as num).toDouble(),
        ),
        minZoom: json['minZoom'] as int,
        maxZoom: json['maxZoom'] as int,
        tileCount: json['tileCount'] as int,
        sizeBytes: json['sizeBytes'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Manages offline tile caching using MBTiles format (SQLite).
///
/// Features:
/// - Download tiles for a bounding box at specified zoom levels
/// - Download tiles for a buffered route corridor
/// - Store tiles in MBTiles format (SQLite)
/// - Report download progress
/// - Cancel ongoing downloads
/// - List and delete cached regions
class OfflineManager {
  static const String _dbName = 'offline_tiles.mbtiles';
  static const String _regionsDbName = 'offline_regions.db';

  // OpenFreeMap tile URL template for vector tiles
  // Note: bright style uses vector tiles served as .mvt
  static const String _tileUrlTemplate =
      'https://tiles.openfreemap.org/planet/{z}/{x}/{y}.mvt';

  // Fallback to MapLibre demo tiles (raster PNG)
  static const String _fallbackTileUrlTemplate =
      'https://demotiles.maplibre.org/tiles/{z}/{x}/{y}.png';

  Database? _tilesDb;
  Database? _regionsDb;
  bool _cancelRequested = false;

  // Concurrency control
  static const int _maxConcurrentDownloads = 6;

  /// Initialize the offline manager and open databases.
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final tilesPath = path.join(dir.path, _dbName);
    final regionsPath = path.join(dir.path, _regionsDbName);

    _tilesDb = await openDatabase(
      tilesPath,
      version: 1,
      onCreate: (db, version) async {
        // MBTiles schema per spec: https://github.com/mapbox/mbtiles-spec
        await db.execute('''
          CREATE TABLE IF NOT EXISTS tiles (
            zoom_level INTEGER NOT NULL,
            tile_column INTEGER NOT NULL,
            tile_row INTEGER NOT NULL,
            tile_data BLOB NOT NULL,
            PRIMARY KEY (zoom_level, tile_column, tile_row)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS metadata (
            name TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        // Initialize metadata
        await db.insert('metadata', {'name': 'name', 'value': 'AlpineNav Offline Tiles'});
        await db.insert('metadata', {'name': 'type', 'value': 'overlay'});
        await db.insert('metadata', {'name': 'version', 'value': '1'});
        await db.insert('metadata', {'name': 'format', 'value': 'mvt'});
      },
    );

    _regionsDb = await openDatabase(
      regionsPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS regions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            minLat REAL NOT NULL,
            minLon REAL NOT NULL,
            maxLat REAL NOT NULL,
            maxLon REAL NOT NULL,
            minZoom INTEGER NOT NULL,
            maxZoom INTEGER NOT NULL,
            tileCount INTEGER NOT NULL,
            sizeBytes INTEGER NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Close databases.
  Future<void> dispose() async {
    await _tilesDb?.close();
    await _regionsDb?.close();
    _tilesDb = null;
    _regionsDb = null;
  }

  /// Download tiles for a bounding box.
  ///
  /// Returns a stream of [DownloadProgress] updates.
  /// The region is saved with the given [regionName] when complete.
  Stream<DownloadProgress> downloadRegion({
    required String regionName,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
  }) async* {
    _cancelRequested = false;

    if (_tilesDb == null || _regionsDb == null) {
      yield const DownloadProgress(
        tilesDownloaded: 0,
        tilesTotal: 0,
        bytesDownloaded: 0,
        isComplete: true,
        error: 'OfflineManager not initialized',
      );
      return;
    }

    // Enumerate all tiles needed
    final tiles = enumerateTileCoords(
      bbox: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    if (tiles.isEmpty) {
      yield const DownloadProgress(
        tilesDownloaded: 0,
        tilesTotal: 0,
        bytesDownloaded: 0,
        isComplete: true,
      );
      return;
    }

    // Filter out already cached tiles
    final tilesToDownload = <TileCoord>[];
    for (final tile in tiles) {
      final exists = await _tileExists(tile);
      if (!exists) {
        tilesToDownload.add(tile);
      }
    }

    final totalTiles = tiles.length;
    final alreadyCached = totalTiles - tilesToDownload.length;
    int downloaded = alreadyCached;
    int bytesDownloaded = 0;
    int failed = 0;

    yield DownloadProgress(
      tilesDownloaded: downloaded,
      tilesTotal: totalTiles,
      bytesDownloaded: bytesDownloaded,
    );

    // Download tiles with concurrency limit
    final client = http.Client();
    try {
      // Process tiles in batches
      for (var i = 0; i < tilesToDownload.length; i += _maxConcurrentDownloads) {
        if (_cancelRequested) {
          yield DownloadProgress(
            tilesDownloaded: downloaded,
            tilesTotal: totalTiles,
            bytesDownloaded: bytesDownloaded,
            tilesFailed: failed,
            isComplete: true,
            error: 'Download cancelled',
          );
          return;
        }

        final batch = tilesToDownload.skip(i).take(_maxConcurrentDownloads).toList();
        final futures = batch.map((tile) => _downloadTile(client, tile));
        final results = await Future.wait(futures, eagerError: false);

        for (final result in results) {
          if (result != null) {
            bytesDownloaded += result;
            downloaded++;
          } else {
            failed++;
            downloaded++; // Count as processed even if failed
          }
        }

        yield DownloadProgress(
          tilesDownloaded: downloaded,
          tilesTotal: totalTiles,
          bytesDownloaded: bytesDownloaded,
          tilesFailed: failed,
        );
      }

      // Save region metadata
      final regionId = DateTime.now().millisecondsSinceEpoch.toString();
      final region = OfflineRegion(
        id: regionId,
        name: regionName,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        tileCount: totalTiles,
        sizeBytes: bytesDownloaded,
        createdAt: DateTime.now(),
      );
      await _saveRegion(region);

      yield DownloadProgress(
        tilesDownloaded: downloaded,
        tilesTotal: totalTiles,
        bytesDownloaded: bytesDownloaded,
        tilesFailed: failed,
        isComplete: true,
      );
    } finally {
      client.close();
    }
  }

  /// Download tiles for a route with a buffer distance.
  ///
  /// [coordinatePairs] should be a list of [lat, lon] pairs from the route.
  /// [bufferMeters] is the distance to buffer around the route (default 5km).
  Stream<DownloadProgress> downloadRouteRegion({
    required String regionName,
    required List<List<double>> coordinatePairs,
    required int minZoom,
    required int maxZoom,
    double bufferMeters = 5000,
  }) async* {
    final bbox = computeRouteBBox(coordinatePairs);
    if (bbox == null) {
      yield const DownloadProgress(
        tilesDownloaded: 0,
        tilesTotal: 0,
        bytesDownloaded: 0,
        isComplete: true,
        error: 'Empty route',
      );
      return;
    }

    final bufferedBBox = computeBufferedBBox(bbox, bufferMeters);

    yield* downloadRegion(
      regionName: regionName,
      bounds: bufferedBBox,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  /// Cancel an ongoing download.
  void cancelDownload() {
    _cancelRequested = true;
  }

  /// List all saved offline regions.
  Future<List<OfflineRegion>> listRegions() async {
    if (_regionsDb == null) return [];

    final rows = await _regionsDb!.query(
      'regions',
      orderBy: 'createdAt DESC',
    );

    return rows.map((row) => OfflineRegion.fromJson(row)).toList();
  }

  /// Delete an offline region.
  ///
  /// Note: This removes the region metadata but tiles remain cached
  /// (they may be shared with other regions). Use [cleanOrphanedTiles]
  /// to remove tiles not belonging to any region.
  Future<void> deleteRegion(String regionId) async {
    if (_regionsDb == null) return;
    await _regionsDb!.delete('regions', where: 'id = ?', whereArgs: [regionId]);
  }

  /// Get total storage used by cached tiles.
  Future<int> getTotalStorageBytes() async {
    if (_tilesDb == null) return 0;

    final result = await _tilesDb!.rawQuery(
      'SELECT SUM(LENGTH(tile_data)) as total FROM tiles',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Get total number of cached tiles.
  Future<int> getTotalTileCount() async {
    if (_tilesDb == null) return 0;

    final result = await _tilesDb!.rawQuery('SELECT COUNT(*) as count FROM tiles');
    return (result.first['count'] as int?) ?? 0;
  }

  /// Check if a tile is cached.
  Future<bool> isTileCached(int z, int x, int y) async {
    return _tileExists(TileCoord(x, y, z));
  }

  /// Get cached tile data.
  Future<Uint8List?> getTile(int z, int x, int y) async {
    if (_tilesDb == null) return null;

    // MBTiles uses TMS y-coordinate (flipped from XYZ)
    final tmsY = (1 << z) - 1 - y;

    final rows = await _tilesDb!.query(
      'tiles',
      columns: ['tile_data'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [z, x, tmsY],
    );

    if (rows.isEmpty) return null;
    return rows.first['tile_data'] as Uint8List;
  }

  /// Clear all cached tiles and regions.
  Future<void> clearAll() async {
    if (_tilesDb != null) {
      await _tilesDb!.delete('tiles');
    }
    if (_regionsDb != null) {
      await _regionsDb!.delete('regions');
    }
  }

  // Private helpers

  Future<bool> _tileExists(TileCoord tile) async {
    if (_tilesDb == null) return false;

    // MBTiles uses TMS y-coordinate (flipped from XYZ)
    final tmsY = (1 << tile.z) - 1 - tile.y;

    final rows = await _tilesDb!.query(
      'tiles',
      columns: ['1'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [tile.z, tile.x, tmsY],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int?> _downloadTile(http.Client client, TileCoord tile) async {
    final url = _tileUrlTemplate
        .replaceAll('{z}', tile.z.toString())
        .replaceAll('{x}', tile.x.toString())
        .replaceAll('{y}', tile.y.toString());

    try {
      final response = await client.get(Uri.parse(url)).timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        await _storeTile(tile, response.bodyBytes);
        return response.bodyBytes.length;
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        // Try fallback tile source
        return _downloadFallbackTile(client, tile);
      }
      return null;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<int?> _downloadFallbackTile(http.Client client, TileCoord tile) async {
    final url = _fallbackTileUrlTemplate
        .replaceAll('{z}', tile.z.toString())
        .replaceAll('{x}', tile.x.toString())
        .replaceAll('{y}', tile.y.toString());

    try {
      final response = await client.get(Uri.parse(url)).timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        await _storeTile(tile, response.bodyBytes);
        return response.bodyBytes.length;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _storeTile(TileCoord tile, Uint8List data) async {
    if (_tilesDb == null) return;

    // MBTiles uses TMS y-coordinate (flipped from XYZ)
    final tmsY = (1 << tile.z) - 1 - tile.y;

    await _tilesDb!.insert(
      'tiles',
      {
        'zoom_level': tile.z,
        'tile_column': tile.x,
        'tile_row': tmsY,
        'tile_data': data,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _saveRegion(OfflineRegion region) async {
    if (_regionsDb == null) return;

    await _regionsDb!.insert(
      'regions',
      region.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
