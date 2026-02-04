import 'dart:math';

// TODO(phase3): Expand with route buffering and tile count estimation
//
// Utility functions for slippy map tile calculations.
// Reference: https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
//
// These are standard Web Mercator (EPSG:3857) tile calculations.

/// Convert longitude to tile X index at a given zoom level.
int lonToTileX(double lon, int zoom) {
  return ((lon + 180.0) / 360.0 * pow(2, zoom)).floor();
}

/// Convert latitude to tile Y index at a given zoom level.
int latToTileY(double lat, int zoom) {
  final latRad = lat * pi / 180.0;
  return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
          2.0 *
          pow(2, zoom))
      .floor();
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

// TODO(phase3): Add function to compute bounding box for a route with buffer
// TODO(phase3): Add function to enumerate all tile coordinates in a bbox
// TODO(phase3): Add function to estimate download size (avg bytes per tile * count)
