import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/tile_calculator.dart';

// Available map tile sources for AlpineNav.
// Vector sources use a remote style JSON URL directly.
// Raster XYZ sources get wrapped in a dynamically generated MapLibre
// style JSON document (MapLibre needs a full style, not a bare tile URL).
// WMS sources are served via a local tile proxy (WmsTileServer).

enum MapSourceType { vector, rasterXyz, wms }

/// Whether this source supports offline downloading.
/// Some raster tile servers (e.g. OpenTopoMap) block bulk downloads.
/// WMS sources use their own download path (via WmsTileServer cache).
extension MapSourceOfflineSupport on MapSource {
  bool get supportsOfflineDownload {
    // OpenTopoMap rate-limits and blocks bulk tile requests
    if (id == 'opentopo') return false;
    // WMS sources support offline via our own tile cache
    if (type == MapSourceType.wms) return true;
    return true;
  }
}

class MapSource {
  final String id;
  final String name;
  final MapSourceType type;

  /// For vector: the style JSON URL. For raster: the XYZ tile URL template.
  /// For WMS: unused (use [wmsBaseUrl] instead).
  final String url;

  final String attribution;

  /// Tile size for raster sources (256 or 512). Ignored for vector.
  final int tileSize;

  /// Average bytes per tile, used for download size estimates.
  final int avgTileSizeBytes;

  // ── WMS-specific fields ──────────────────────────────────────────

  /// WMS endpoint base URL (e.g. the MapServer CGI URL).
  final String? wmsBaseUrl;

  /// WMS layer name(s) for GetMap requests.
  final String? wmsLayers;

  /// Coordinate reference system for WMS requests (default: EPSG:3857).
  final String wmsCrs;

  /// Image format for WMS responses (default: image/jpeg).
  final String wmsFormat;

  const MapSource({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    required this.attribution,
    this.tileSize = 256,
    this.avgTileSizeBytes = 25000,
    this.wmsBaseUrl,
    this.wmsLayers,
    this.wmsCrs = 'EPSG:3857',
    this.wmsFormat = 'image/jpeg',
  });

  /// Build a WMS GetMap URL for the given tile coordinate.
  ///
  /// Only valid for [MapSourceType.wms] sources.
  String buildWmsGetMapUrl(int z, int x, int y) {
    assert(type == MapSourceType.wms, 'buildWmsGetMapUrl called on non-WMS source');
    final bbox = getTileEpsg3857BBox(z, x, y);
    final separator = wmsBaseUrl!.contains('?') ? '&' : '?';
    // Use WMS 1.1.0 for consistent X,Y bbox order across all CRS.
    // WMS 1.3.0 requires Y,X order for EPSG:3857, which is error-prone.
    return '$wmsBaseUrl$separator'
        'SERVICE=WMS&VERSION=1.1.0&REQUEST=GetMap'
        '&LAYERS=$wmsLayers'
        '&STYLES='
        '&SRS=$wmsCrs'
        '&BBOX=${bbox.minX},${bbox.minY},${bbox.maxX},${bbox.maxY}'
        '&WIDTH=$tileSize&HEIGHT=$tileSize'
        '&FORMAT=$wmsFormat';
  }

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

  // ── WMS sources ─────────────────────────────────────────────────

  static const trentinoOrthophoto = MapSource(
    id: 'trentino_ortho',
    name: 'Trentino Orthophoto 2015',
    type: MapSourceType.wms,
    url: '',
    wmsBaseUrl:
        'https://siat.provincia.tn.it/geoserver/stem/ecw-rgb-2015/wms',
    wmsLayers: 'ecw-rgb-2015',
    wmsCrs: 'EPSG:3857',
    wmsFormat: 'image/jpeg',
    attribution: '© Provincia Autonoma di Trento',
    tileSize: 512,
    avgTileSizeBytes: 200000, // 512px tiles from 0.2m orthophoto = ~200KB each
  );

  static const trentinoLidarShading = MapSource(
    id: 'trentino_lidar',
    name: 'Trentino LiDAR Hillshade (315°)',
    type: MapSourceType.wms,
    url: '',
    wmsBaseUrl:
        'https://siat.provincia.tn.it/geoserver/stem/dtm_315_wg/wms',
    wmsLayers: 'dtm_315_wg', // DTM hillshade with 315° azimuth (northwest lighting)
    wmsCrs: 'EPSG:3857',
    wmsFormat: 'image/jpeg',
    attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
    tileSize: 512,
    avgTileSizeBytes: 80000, // 512px grayscale hillshade = ~80KB each
  );

  static const trentinoLidarShading135 = MapSource(
    id: 'trentino_lidar_135',
    name: 'Trentino LiDAR Hillshade (135°)',
    type: MapSourceType.wms,
    url: '',
    wmsBaseUrl:
        'https://siat.provincia.tn.it/geoserver/stem/dtm_135_wg/wms',
    wmsLayers: 'dtm_135_wg', // DTM hillshade with 135° azimuth (southwest lighting, complementary view)
    wmsCrs: 'EPSG:3857',
    wmsFormat: 'image/jpeg',
    attribution: '© Provincia Autonoma di Trento - LiDAR DTM',
    tileSize: 512,
    avgTileSizeBytes: 80000,
  );

  static const trentinoSurfaceShading = MapSource(
    id: 'trentino_dsm',
    name: 'Trentino DSM Hillshade (315°)',
    type: MapSourceType.wms,
    url: '',
    wmsBaseUrl:
        'https://siat.provincia.tn.it/geoserver/stem/dsm_315_wg/wms',
    wmsLayers: 'dsm_315_wg', // DSM (Digital Surface Model) includes buildings and vegetation
    wmsCrs: 'EPSG:3857',
    wmsFormat: 'image/jpeg',
    attribution: '© Provincia Autonoma di Trento - LiDAR DSM',
    tileSize: 512,
    avgTileSizeBytes: 80000,
  );

  static const trentinoSurfaceShading135 = MapSource(
    id: 'trentino_dsm_135',
    name: 'Trentino DSM Hillshade (135°)',
    type: MapSourceType.wms,
    url: '',
    wmsBaseUrl:
        'https://siat.provincia.tn.it/geoserver/stem/dsm_135_wg/wms',
    wmsLayers: 'dsm_135_wg', // DSM with alternate lighting angle
    wmsCrs: 'EPSG:3857',
    wmsFormat: 'image/jpeg',
    attribution: '© Provincia Autonoma di Trento - LiDAR DSM',
    tileSize: 512,
    avgTileSizeBytes: 80000,
  );

  /// All available map sources, in display order.
  static const List<MapSource> all = [
    openFreeMap,
    openTopoMap,
    esriWorldImagery,
    trentinoOrthophoto,
    trentinoLidarShading,
    trentinoLidarShading135,
    trentinoSurfaceShading,
    trentinoSurfaceShading135,
  ];

  /// Look up a source by id. Returns [openFreeMap] if not found.
  static MapSource byId(String id, {List<MapSource> customSources = const []}) {
    // Check custom sources first
    for (final s in customSources) {
      if (s.id == id) return s;
    }
    // Then check built-in sources
    for (final s in all) {
      if (s.id == id) return s;
    }
    return openFreeMap;
  }

  /// Get all available sources (built-in + custom), grouped by type.
  ///
  /// Returns sources in display order: base maps first, then WMS sources
  /// (built-in WMS followed by custom WMS).
  static List<MapSource> allWithCustom(List<MapSource> customSources) {
    // Base maps (vector + raster XYZ)
    final baseMaps = all.where((s) => s.type != MapSourceType.wms).toList();
    // Built-in WMS
    final builtinWms = all.where((s) => s.type == MapSourceType.wms).toList();
    // Custom WMS (already filtered by CustomWmsService)
    return [...baseMaps, ...builtinWms, ...customSources];
  }

  // ── Style string for MapLibre ───────────────────────────────────

  /// Returns the style string to pass to [MapLibreMap.styleString].
  ///
  /// Vector sources return the URL directly. Raster XYZ sources return
  /// an inline JSON style document that MapLibre can parse.
  /// WMS sources require [wmsStyleString] instead (needs the tile server port).
  String get styleString {
    if (type == MapSourceType.vector) return url;
    if (type == MapSourceType.wms) {
      // Caller should use wmsStyleString(port) instead.
      // Return empty style as a safe fallback.
      return '{"version":8,"name":"empty","sources":{},"layers":[]}';
    }
    return _buildRasterStyleJson();
  }

  /// Build a MapLibre style string for a WMS source, using the local tile
  /// server at the given [port] to proxy tile requests.
  ///
  /// Used when the device is **online** — MapLibre fetches tiles from the
  /// localhost HTTP proxy, which forwards to the WMS endpoint and caches.
  String wmsStyleString(int port) {
    assert(type == MapSourceType.wms);
    final tileUrl = 'http://127.0.0.1:$port/wms/$id/{z}/{x}/{y}.jpg';
    return _buildWmsStyle(tileUrl);
  }

  /// Build a MapLibre style string for a WMS source that reads tiles directly
  /// from the disk cache via `file://` URLs.
  ///
  /// Used when the device is **offline** — MapLibre Native stops making HTTP
  /// requests (including to localhost) when Android reports no connectivity,
  /// so we bypass the tile server entirely and point at cached files on disk.
  String wmsOfflineStyleString(String cacheDirPath) {
    assert(type == MapSourceType.wms);
    final tileUrl = 'file://$cacheDirPath/$id/{z}/{x}/{y}.jpg';
    return _buildWmsStyle(tileUrl);
  }

  String _buildWmsStyle(String tileUrl) {
    final escapedAttribution = attribution.replaceAll('"', '\\"');
    // Source maxzoom controls the highest zoom at which MapLibre requests new
    // tiles.  Beyond this level it over-zooms (stretches) the last fetched tile
    // instead of going black.  We set it high (22) so the WMS server is queried
    // up to z22; for zoom levels the server can't serve, the proxy returns a
    // transparent tile and MapLibre gracefully falls back to the previous zoom.
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
