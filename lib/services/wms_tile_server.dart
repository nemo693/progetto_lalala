import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/map_source.dart';

/// Local HTTP tile server that proxies WMS requests and caches tiles to disk.
///
/// MapLibre fetches tiles from `http://127.0.0.1:{port}/wms/{sourceId}/{z}/{x}/{y}.jpg`.
/// For each request, the server checks the disk cache first. On a cache miss,
/// it builds a WMS GetMap URL, fetches the tile, caches it, and serves it.
class WmsTileServer {
  static HttpServer? _server;
  static int? _port;
  static final Map<String, MapSource> _sources = {};
  static Directory? _cacheDir;

  /// Start the tile server. Returns the port number.
  /// If already running, returns the existing port.
  static Future<int> start() async {
    if (_server != null) return _port!;

    // Initialize cache directory
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/wms_cache');

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[WmsTileServer] listening on port $_port');

    _server!.listen(_handleRequest);
    return _port!;
  }

  /// Register a WMS source for proxying.
  static void registerSource(MapSource source) {
    assert(source.type == MapSourceType.wms);
    _sources[source.id] = source;
  }

  /// Stop the server.
  static Future<void> stop() async {
    _sources.clear();
    await _server?.close(force: true);
    _server = null;
    _port = null;
    debugPrint('[WmsTileServer] stopped');
  }

  /// Whether the server is currently running.
  static bool get isRunning => _server != null;

  /// The port the server is listening on, or null if not running.
  static int? get port => _port;

  /// Delete all cached tiles for a source.
  static Future<void> clearCache(String sourceId) async {
    if (_cacheDir == null) return;
    final dir = Directory('${_cacheDir!.path}/$sourceId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      debugPrint('[WmsTileServer] cleared cache for $sourceId');
    }
  }

  /// Get total cache size in bytes across all sources.
  static Future<int> getCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    int total = 0;
    await for (final entity in _cacheDir!.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Get cache size for a specific source.
  static Future<int> getCacheSizeForSource(String sourceId) async {
    if (_cacheDir == null) return 0;
    final dir = Directory('${_cacheDir!.path}/$sourceId');
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  // ── Request handling ──────────────────────────────────────────────

  static Future<void> _handleRequest(HttpRequest request) async {
    // Expected path: /wms/{sourceId}/{z}/{x}/{y}.jpg
    final segments = request.uri.pathSegments;
    if (segments.length != 5 || segments[0] != 'wms') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
      return;
    }

    final sourceId = segments[1];
    final z = int.tryParse(segments[2]);
    final x = int.tryParse(segments[3]);
    final yWithExt = segments[4];
    final y = int.tryParse(yWithExt.split('.').first);

    if (z == null || x == null || y == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid tile coordinates')
        ..close();
      return;
    }

    // Always try cache first — even if the source isn't registered
    // (e.g. offline mode with previously downloaded tiles)
    final cached = await _getCachedTile(sourceId, z, x, y);
    if (cached != null) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'jpeg')
        ..add(cached)
        ..close();
      return;
    }

    // Cache miss — try to fetch from WMS if the source is registered
    final source = _sources[sourceId];
    if (source == null) {
      // Source not registered and not in cache — nothing we can do
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Tile not cached and source not registered: $sourceId')
        ..close();
      return;
    }

    final bytes = await _fetchWmsTile(source, z, x, y);
    if (bytes != null) {
      // Cache the tile (fire and forget)
      _cacheTile(sourceId, z, x, y, bytes);

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'jpeg')
        ..add(bytes)
        ..close();
    } else {
      // Return 404 — MapLibre will show empty tile
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Tile fetch failed')
        ..close();
    }
  }

  // ── WMS fetching with retries ─────────────────────────────────────

  /// Fetch a tile from the WMS endpoint with retries.
  static Future<Uint8List?> _fetchWmsTile(
      MapSource source, int z, int x, int y) {
    return fetchWmsTile(source, z, x, y);
  }

  /// Fetch a tile from the WMS endpoint with retries.
  /// Public so the offline downloader can use it directly.
  static Future<Uint8List?> fetchWmsTile(
      MapSource source, int z, int x, int y) async {
    final url = source.buildWmsGetMapUrl(z, x, y);
    const maxRetries = 3;
    const retryDelays = [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          // Verify the response is actually an image, not an XML error
          final contentType = response.headers['content-type'] ?? '';
          if (contentType.contains('image/')) {
            return response.bodyBytes;
          }
          // Non-image response (e.g. XML ServiceException) — don't retry,
          // it's a server-side issue that won't resolve on its own.
          debugPrint('[WmsTileServer] WMS returned non-image content-type '
              '"$contentType" for $z/$x/$y — not retrying');
          return null;
        } else {
          debugPrint('[WmsTileServer] HTTP ${response.statusCode} for '
              '$z/$x/$y (attempt ${attempt + 1})');
        }
      } on TimeoutException {
        debugPrint(
            '[WmsTileServer] Timeout for $z/$x/$y (attempt ${attempt + 1})');
      } catch (e) {
        debugPrint(
            '[WmsTileServer] Error for $z/$x/$y (attempt ${attempt + 1}): $e');
      }

      if (attempt < maxRetries - 1) {
        await Future.delayed(retryDelays[attempt]);
      }
    }
    return null;
  }

  // ── Disk cache ────────────────────────────────────────────────────

  static File _cacheFile(String sourceId, int z, int x, int y) {
    return File('${_cacheDir!.path}/$sourceId/$z/$x/$y.jpg');
  }

  static Future<Uint8List?> _getCachedTile(
      String sourceId, int z, int x, int y) async {
    final file = _cacheFile(sourceId, z, x, y);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty && _isValidImage(bytes)) return bytes;
      // Delete corrupted cache entry (e.g. XML error cached as .jpg)
      if (bytes.isNotEmpty) {
        debugPrint('[WmsTileServer] Removing corrupted cached tile $z/$x/$y');
        try { await file.delete(); } catch (_) {}
      }
    }
    return null;
  }

  /// Check if bytes look like a valid image (JPEG or PNG).
  /// JPEG starts with FF D8 FF, PNG starts with 89 50 4E 47.
  static bool _isValidImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // JPEG magic bytes
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG magic bytes
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    return false;
  }

  static Future<void> _cacheTile(
      String sourceId, int z, int x, int y, Uint8List bytes) async {
    try {
      final file = _cacheFile(sourceId, z, x, y);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('[WmsTileServer] Cache write error: $e');
    }
  }

  /// Check if a tile is in the cache **and** contains valid image data.
  /// Public so the offline downloader can skip already-cached tiles.
  static Future<bool> isTileCached(
      String sourceId, int z, int x, int y) async {
    if (_cacheDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/wms_cache');
    }
    final file = _cacheFile(sourceId, z, x, y);
    if (!await file.exists()) return false;
    // Validate the cached bytes are a real image (not empty or XML error)
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || !_isValidImage(bytes)) {
        // Remove corrupted entry so it gets re-downloaded
        debugPrint('[WmsTileServer] Removing invalid cached tile $z/$x/$y');
        try { await file.delete(); } catch (_) {}
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Write a tile to the cache. Public for the offline downloader.
  static Future<void> cacheTile(
      String sourceId, int z, int x, int y, Uint8List bytes) async {
    if (_cacheDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/wms_cache');
    }
    await _cacheTile(sourceId, z, x, y, bytes);
  }
}
