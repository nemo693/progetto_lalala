import 'dart:io';

import 'package:flutter/foundation.dart';

// Available map tile sources for AlpineNav.
// Vector sources use a remote style JSON URL directly.
// Raster XYZ sources get wrapped in a dynamically generated MapLibre
// style JSON document (MapLibre needs a full style, not a bare tile URL).

enum MapSourceType { vector, rasterXyz }

/// Whether this source supports offline downloading.
/// Some raster tile servers (e.g. OpenTopoMap) block bulk downloads.
extension MapSourceOfflineSupport on MapSource {
  bool get supportsOfflineDownload {
    // OpenTopoMap rate-limits and blocks bulk tile requests
    if (id == 'opentopo') return false;
    return true;
  }
}

class MapSource {
  final String id;
  final String name;
  final MapSourceType type;

  /// For vector: the style JSON URL. For raster: the XYZ tile URL template.
  final String url;

  final String attribution;

  /// Tile size for raster sources (256 or 512). Ignored for vector.
  final int tileSize;

  /// Average bytes per tile, used for download size estimates.
  final int avgTileSizeBytes;

  const MapSource({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    required this.attribution,
    this.tileSize = 256,
    this.avgTileSizeBytes = 25000,
  });

  // ── Built-in sources ────────────────────────────────────────────

  static const openFreeMap = MapSource(
    id: 'openfree',
    name: 'OpenFreeMap',
    type: MapSourceType.vector,
    url: 'https://tiles.openfreemap.org/styles/bright',
    attribution: '© OpenFreeMap © OpenStreetMap contributors',
    avgTileSizeBytes: 25000,
  );

  static const openTopoMap = MapSource(
    id: 'opentopo',
    name: 'OpenTopoMap',
    type: MapSourceType.rasterXyz,
    url: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    attribution:
        'Map data: © OpenStreetMap contributors, SRTM | '
        'Map style: © OpenTopoMap (CC-BY-SA)',
    tileSize: 256,
    avgTileSizeBytes: 40000,
  );

  static const esriWorldImagery = MapSource(
    id: 'esri_imagery',
    name: 'Satellite',
    type: MapSourceType.rasterXyz,
    url:
        'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution:
        'Tiles © Esri — Source: Esri, i-cubed, USDA, USGS, AEX, '
        'GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, '
        'and the GIS User Community',
    tileSize: 256,
    avgTileSizeBytes: 50000,
  );

  /// All available sources, in display order.
  static const List<MapSource> all = [
    openFreeMap,
    openTopoMap,
    esriWorldImagery,
  ];

  /// Look up a source by id. Returns [openFreeMap] if not found.
  static MapSource byId(String id) {
    return all.firstWhere((s) => s.id == id, orElse: () => openFreeMap);
  }

  // ── Style string for MapLibre ───────────────────────────────────

  /// Returns the style string to pass to [MapLibreMap.styleString].
  ///
  /// Vector sources return the URL directly. Raster XYZ sources return
  /// an inline JSON style document that MapLibre can parse.
  String get styleString {
    if (type == MapSourceType.vector) return url;
    return _buildRasterStyleJson();
  }

  String _buildRasterStyleJson() {
    // Escape any quotes in attribution for valid JSON
    final escapedAttribution = attribution.replaceAll('"', '\\"');
    return '{'
        '"version":8,'
        '"name":"$name",'
        '"sources":{'
        '"raster-tiles":{'
        '"type":"raster",'
        '"tiles":["$url"],'
        '"tileSize":$tileSize,'
        '"attribution":"$escapedAttribution"'
        '}'
        '},'
        '"layers":[{'
        '"id":"raster-layer",'
        '"type":"raster",'
        '"source":"raster-tiles",'
        '"minzoom":0,'
        '"maxzoom":19'
        '}]'
        '}';
  }

  /// Returns a URL that MapLibre's native offline API can use.
  ///
  /// Vector sources return the remote style URL directly.
  /// Raster XYZ sources need a URL pointing to a valid MapLibre style JSON.
  /// We spin up a tiny local HTTP server to serve the inline style JSON,
  /// because MapLibre Native's offline downloader reliably handles http://
  /// URLs but file:// URLs are unreliable on Android.
  Future<String> get offlineStyleUrl async {
    if (type == MapSourceType.vector) return url;

    final jsonContent = _buildRasterStyleJson();
    final styleUrl = await LocalStyleServer.serve(id, jsonContent);
    debugPrint('[MapSource] offlineStyleUrl for $id: $styleUrl');
    return styleUrl;
  }
}

/// A tiny local HTTP server that serves style JSON strings for the offline
/// downloader. MapLibre Native's downloadOfflineRegion reliably fetches
/// http:// URLs but file:// is unreliable on Android.
///
/// The server stays alive until [stopAll] is called (after download completes).
class LocalStyleServer {
  static HttpServer? _server;
  static final Map<String, String> _styles = {};

  /// Serve [jsonContent] at `http://127.0.0.1:{port}/style/{id}.json`.
  /// Returns the full URL. Starts the server if not already running.
  static Future<String> serve(String id, String jsonContent) async {
    _styles[id] = jsonContent;

    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[LocalStyleServer] listening on port ${_server!.port}');
      _server!.listen((request) {
        // Expected path: /style/<id>.json
        final segments = request.uri.pathSegments;
        if (segments.length == 2 && segments[0] == 'style') {
          final styleId = segments[1].replaceAll('.json', '');
          final body = _styles[styleId];
          if (body != null) {
            debugPrint('[LocalStyleServer] serving style for $styleId');
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(body)
              ..close();
            return;
          }
        }
        debugPrint('[LocalStyleServer] 404: ${request.uri}');
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
      });
    }

    return 'http://127.0.0.1:${_server!.port}/style/$id.json';
  }

  /// Stop the server and clear cached styles. Call after download finishes.
  static Future<void> stopAll() async {
    _styles.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('[LocalStyleServer] stopped');
  }
}
