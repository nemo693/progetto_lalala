// Available map tile sources for AlpineNav.
// Vector sources use a remote style JSON URL directly.
// Raster XYZ sources get wrapped in a dynamically generated MapLibre
// style JSON document (MapLibre needs a full style, not a bare tile URL).

enum MapSourceType { vector, rasterXyz }

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
}
