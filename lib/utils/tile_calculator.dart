import 'dart:math';

// Utility functions for slippy map tile calculations.
// Reference: https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
//
// These are standard Web Mercator (EPSG:3857) tile calculations.

/// Convert longitude to tile X index at a given zoom level.
///
/// Clamps result to valid tile range [0, 2^zoom - 1].
///
/// Note: We clamp rather than wrap because this function is primarily used
/// for bounding box tile enumeration. For a bbox from lon A to lon B, we need
/// lonToTileX(B) >= lonToTileX(A). Wrapping lon=180 to -180 would break this.
/// The clamp ensures lon=180 returns the easternmost tile, which is correct
/// for "include all tiles that intersect this bbox" semantics.
int lonToTileX(double lon, int zoom) {
  final maxTile = (1 << zoom) - 1; // 2^zoom - 1
  final x = ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  return x.clamp(0, maxTile);
}

/// Convert latitude to tile Y index at a given zoom level.
///
/// Clamps to valid range [0, 2^zoom - 1] to handle edge coordinates.
/// Web Mercator is defined for latitudes ~[-85.051, 85.051].
int latToTileY(double lat, int zoom) {
  final maxTile = (1 << zoom) - 1; // 2^zoom - 1
  // Clamp latitude to Web Mercator bounds to avoid math errors
  final clampedLat = lat.clamp(-85.0511, 85.0511);
  final latRad = clampedLat * pi / 180.0;
  final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
          2.0 *
          (1 << zoom))
      .floor();
  return y.clamp(0, maxTile);
}

/// Convert tile X index back to longitude (west edge of tile).
double tileXToLon(int x, int zoom) {
  return x / pow(2, zoom) * 360.0 - 180.0;
}

/// Convert tile Y index back to latitude (north edge of tile).
double tileYToLat(int y, int zoom) {
  final n = pi - 2.0 * pi * y / pow(2, zoom);
  return 180.0 / pi * atan(0.5 * (exp(n) - exp(-n)));
}

/// Count the number of tiles in a bounding box across a range of zoom levels.
///
/// Returns a map of zoom level -> tile count.
Map<int, int> countTilesInBBox({
  required double minLat,
  required double minLon,
  required double maxLat,
  required double maxLon,
  required int minZoom,
  required int maxZoom,
}) {
  final counts = <int, int>{};
  for (var z = minZoom; z <= maxZoom; z++) {
    final xMin = lonToTileX(minLon, z);
    final xMax = lonToTileX(maxLon, z);
    final yMin = latToTileY(maxLat, z); // Note: y is inverted
    final yMax = latToTileY(minLat, z);
    counts[z] = (xMax - xMin + 1) * (yMax - yMin + 1);
  }
  return counts;
}

/// A simple bounding box with min/max lat/lon.
class BoundingBox {
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  const BoundingBox({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  /// Check if the bounding box is valid (non-empty).
  bool get isValid => minLat < maxLat && minLon < maxLon;

  @override
  String toString() =>
      'BoundingBox(minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon)';
}

/// A tile coordinate (x, y) at a specific zoom level.
class TileCoord {
  final int x;
  final int y;
  final int z;

  const TileCoord(this.x, this.y, this.z);

  @override
  bool operator ==(Object other) =>
      other is TileCoord && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'TileCoord($z/$x/$y)';
}

/// Compute the bounding box for a list of coordinate pairs.
///
/// Each pair should be [latitude, longitude].
BoundingBox? computeRouteBBox(List<List<double>> coordinatePairs) {
  if (coordinatePairs.isEmpty) return null;

  double minLat = double.infinity;
  double maxLat = double.negativeInfinity;
  double minLon = double.infinity;
  double maxLon = double.negativeInfinity;

  for (final pair in coordinatePairs) {
    if (pair.length < 2) continue;
    final lat = pair[0];
    final lon = pair[1];
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lon < minLon) minLon = lon;
    if (lon > maxLon) maxLon = lon;
  }

  if (minLat == double.infinity) return null;

  return BoundingBox(
    minLat: minLat,
    minLon: minLon,
    maxLat: maxLat,
    maxLon: maxLon,
  );
}

/// Expand a bounding box by a buffer distance in meters.
///
/// Uses approximate degrees conversion (accurate enough for offline tile downloads):
/// - 1 degree latitude ≈ 111,000 meters
/// - 1 degree longitude ≈ 111,000 * cos(latitude) meters
BoundingBox computeBufferedBBox(BoundingBox bbox, double bufferMeters) {
  // Approximate conversion from meters to degrees
  const metersPerDegreeLat = 111000.0;

  // Use center latitude for longitude conversion
  final centerLat = (bbox.minLat + bbox.maxLat) / 2.0;
  final metersPerDegreeLon = 111000.0 * cos(centerLat * pi / 180.0);

  final latBuffer = bufferMeters / metersPerDegreeLat;
  final lonBuffer = bufferMeters / metersPerDegreeLon;

  return BoundingBox(
    minLat: (bbox.minLat - latBuffer).clamp(-85.0, 85.0),
    minLon: (bbox.minLon - lonBuffer).clamp(-180.0, 180.0),
    maxLat: (bbox.maxLat + latBuffer).clamp(-85.0, 85.0),
    maxLon: (bbox.maxLon + lonBuffer).clamp(-180.0, 180.0),
  );
}

/// Enumerate all tile coordinates within a bounding box for a range of zoom levels.
///
/// Returns a list of [TileCoord] representing each tile to download.
List<TileCoord> enumerateTileCoords({
  required BoundingBox bbox,
  required int minZoom,
  required int maxZoom,
}) {
  final coords = <TileCoord>[];

  for (var z = minZoom; z <= maxZoom; z++) {
    final xMin = lonToTileX(bbox.minLon, z);
    final xMax = lonToTileX(bbox.maxLon, z);
    final yMin = latToTileY(bbox.maxLat, z); // Note: y is inverted in tile coords
    final yMax = latToTileY(bbox.minLat, z);

    for (var x = xMin; x <= xMax; x++) {
      for (var y = yMin; y <= yMax; y++) {
        coords.add(TileCoord(x, y, z));
      }
    }
  }

  return coords;
}

/// Estimate download size in bytes for a list of tile coordinates.
///
/// Uses an average tile size (PNG raster tiles are typically 15-40KB).
/// Default assumes 25KB average for OpenFreeMap bright tiles.
int estimateDownloadSize(List<TileCoord> tiles, {int avgTileSizeBytes = 25000}) {
  return tiles.length * avgTileSizeBytes;
}

/// Compute the EPSG:3857 (Web Mercator) bounding box for a tile coordinate.
///
/// Returns the bbox as (minX, minY, maxX, maxY) in meters.
/// Used to construct WMS GetMap requests for a given tile.
({double minX, double minY, double maxX, double maxY}) getTileEpsg3857BBox(
    int z, int x, int y) {
  const originShift = 20037508.342789244; // pi * 6378137.0
  final tileCount = 1 << z; // 2^z
  final tileSize = (2 * originShift) / tileCount;

  final minX = -originShift + x * tileSize;
  final maxX = minX + tileSize;
  // Y is inverted: tile y=0 is at the top (north)
  final maxY = originShift - y * tileSize;
  final minY = maxY - tileSize;

  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

/// Format bytes as human-readable string.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
