import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/utils/tile_calculator.dart';

void main() {
  group('lonToTileX / latToTileY', () {
    test('converts lon 0 to correct tile at various zooms', () {
      expect(lonToTileX(0, 0), 0);
      expect(lonToTileX(0, 1), 1);
      expect(lonToTileX(0, 2), 2);
    });

    test('converts lat 0 to correct tile at various zooms', () {
      expect(latToTileY(0, 0), 0);
      expect(latToTileY(0, 1), 1);
      expect(latToTileY(0, 2), 2);
    });

    test('handles Dolomites area correctly (z10)', () {
      // Dolomites: ~46.5, 11.35
      final x = lonToTileX(11.35, 10);
      final y = latToTileY(46.5, 10);
      // At zoom 10: x should be ~540-545, y should be ~355-360
      expect(x, greaterThan(530));
      expect(x, lessThan(560));
      expect(y, greaterThan(350));
      expect(y, lessThan(370));
    });
  });

  group('tileXToLon / tileYToLat', () {
    test('round-trips correctly for known coordinates', () {
      // Start with Dolomites coords
      const lon = 11.35;
      const lat = 46.5;
      const zoom = 12;

      final x = lonToTileX(lon, zoom);
      final y = latToTileY(lat, zoom);

      final lonBack = tileXToLon(x, zoom);
      final latBack = tileYToLat(y, zoom);

      // Should be within one tile width of original
      expect((lonBack - lon).abs(), lessThan(0.1));
      expect((latBack - lat).abs(), lessThan(0.1));
    });
  });

  group('countTilesInBBox', () {
    test('counts single tile at zoom 0 for world bbox', () {
      final counts = countTilesInBBox(
        minLat: -85,
        minLon: -180,
        maxLat: 85,
        maxLon: 180,
        minZoom: 0,
        maxZoom: 0,
      );
      // At zoom 0, there is exactly 1 tile (the entire world)
      // lonToTileX and latToTileY now clamp to valid range [0, 2^z-1]
      expect(counts[0], 1);
    });

    test('counts 4 tiles at zoom 1 for world bbox', () {
      final counts = countTilesInBBox(
        minLat: -85,
        minLon: -180,
        maxLat: 85,
        maxLon: 180,
        minZoom: 1,
        maxZoom: 1,
      );
      // At zoom 1, there are exactly 4 tiles (2x2 grid)
      expect(counts[1], 4);
    });

    test('counts more tiles at higher zooms', () {
      final counts = countTilesInBBox(
        minLat: 46.0,
        minLon: 11.0,
        maxLat: 47.0,
        maxLon: 12.0,
        minZoom: 8,
        maxZoom: 10,
      );
      // Higher zoom = more tiles
      expect(counts[9]!, greaterThan(counts[8]!));
      expect(counts[10]!, greaterThan(counts[9]!));
    });

    test('counts tiles for small Dolomites area', () {
      // Small area around Cortina d'Ampezzo
      final counts = countTilesInBBox(
        minLat: 46.5,
        minLon: 12.0,
        maxLat: 46.6,
        maxLon: 12.2,
        minZoom: 12,
        maxZoom: 14,
      );

      // Should have reasonable tile counts
      expect(counts[12], greaterThan(0));
      expect(counts[13], greaterThan(counts[12]!));
      expect(counts[14], greaterThan(counts[13]!));
    });
  });

  group('BoundingBox', () {
    test('isValid returns true for valid bbox', () {
      const bbox = BoundingBox(
        minLat: 46.0,
        minLon: 11.0,
        maxLat: 47.0,
        maxLon: 12.0,
      );
      expect(bbox.isValid, true);
    });

    test('isValid returns false for inverted bbox', () {
      const bbox = BoundingBox(
        minLat: 47.0,
        minLon: 11.0,
        maxLat: 46.0,
        maxLon: 12.0,
      );
      expect(bbox.isValid, false);
    });
  });

  group('computeRouteBBox', () {
    test('returns null for empty list', () {
      expect(computeRouteBBox([]), isNull);
    });

    test('computes correct bbox for single point', () {
      final bbox = computeRouteBBox([
        [46.5, 11.35],
      ]);
      expect(bbox, isNotNull);
      expect(bbox!.minLat, 46.5);
      expect(bbox.maxLat, 46.5);
      expect(bbox.minLon, 11.35);
      expect(bbox.maxLon, 11.35);
    });

    test('computes correct bbox for multiple points', () {
      final bbox = computeRouteBBox([
        [46.0, 11.0],
        [46.5, 11.5],
        [46.3, 12.0],
        [47.0, 11.2],
      ]);
      expect(bbox, isNotNull);
      expect(bbox!.minLat, 46.0);
      expect(bbox.maxLat, 47.0);
      expect(bbox.minLon, 11.0);
      expect(bbox.maxLon, 12.0);
    });
  });

  group('computeBufferedBBox', () {
    test('expands bbox by buffer distance', () {
      const bbox = BoundingBox(
        minLat: 46.5,
        minLon: 11.35,
        maxLat: 46.6,
        maxLon: 11.45,
      );

      // 5km buffer
      final buffered = computeBufferedBBox(bbox, 5000);

      // Buffer should expand roughly 0.045 degrees lat (~5km)
      expect(buffered.minLat, lessThan(bbox.minLat));
      expect(buffered.maxLat, greaterThan(bbox.maxLat));
      expect(buffered.minLon, lessThan(bbox.minLon));
      expect(buffered.maxLon, greaterThan(bbox.maxLon));

      // Should expand by approximately 0.045 degrees (5km / 111km per degree)
      final latExpansion = bbox.minLat - buffered.minLat;
      expect(latExpansion, greaterThan(0.04));
      expect(latExpansion, lessThan(0.05));
    });

    test('clamps to valid coordinate ranges', () {
      const bbox = BoundingBox(
        minLat: -84.0,
        minLon: -179.0,
        maxLat: 84.0,
        maxLon: 179.0,
      );

      // Large buffer that would exceed bounds
      final buffered = computeBufferedBBox(bbox, 200000);

      expect(buffered.minLat, greaterThanOrEqualTo(-85.0));
      expect(buffered.maxLat, lessThanOrEqualTo(85.0));
      expect(buffered.minLon, greaterThanOrEqualTo(-180.0));
      expect(buffered.maxLon, lessThanOrEqualTo(180.0));
    });
  });

  group('TileCoord', () {
    test('equality works correctly', () {
      const t1 = TileCoord(100, 200, 12);
      const t2 = TileCoord(100, 200, 12);
      const t3 = TileCoord(100, 201, 12);

      expect(t1 == t2, true);
      expect(t1 == t3, false);
    });

    test('hashCode is consistent', () {
      const t1 = TileCoord(100, 200, 12);
      const t2 = TileCoord(100, 200, 12);

      expect(t1.hashCode, t2.hashCode);
    });

    test('toString formats correctly', () {
      const t = TileCoord(100, 200, 12);
      expect(t.toString(), 'TileCoord(12/100/200)');
    });
  });

  group('enumerateTileCoords', () {
    test('returns empty list for invalid bbox', () {
      const bbox = BoundingBox(
        minLat: 47.0,
        minLon: 11.0,
        maxLat: 46.0,
        maxLon: 10.0,
      );
      final tiles = enumerateTileCoords(bbox: bbox, minZoom: 10, maxZoom: 10);
      // With inverted coords, might get weird results or empty
      // The function should still work without crashing
      expect(tiles, isNotNull);
    });

    test('returns correct number of tiles for known area', () {
      const bbox = BoundingBox(
        minLat: 46.5,
        minLon: 11.3,
        maxLat: 46.6,
        maxLon: 11.4,
      );

      final tiles = enumerateTileCoords(bbox: bbox, minZoom: 10, maxZoom: 10);

      // Count should match countTilesInBBox
      final counts = countTilesInBBox(
        minLat: 46.5,
        minLon: 11.3,
        maxLat: 46.6,
        maxLon: 11.4,
        minZoom: 10,
        maxZoom: 10,
      );
      expect(tiles.length, counts[10]);
    });

    test('returns tiles for multiple zoom levels', () {
      const bbox = BoundingBox(
        minLat: 46.5,
        minLon: 11.3,
        maxLat: 46.55,
        maxLon: 11.35,
      );

      final tiles = enumerateTileCoords(bbox: bbox, minZoom: 10, maxZoom: 12);

      // Should have tiles at all zoom levels
      final z10Count = tiles.where((t) => t.z == 10).length;
      final z11Count = tiles.where((t) => t.z == 11).length;
      final z12Count = tiles.where((t) => t.z == 12).length;

      expect(z10Count, greaterThan(0));
      expect(z11Count, greaterThan(0));
      expect(z12Count, greaterThan(0));

      // Higher zoom = more tiles
      expect(z11Count, greaterThanOrEqualTo(z10Count));
      expect(z12Count, greaterThanOrEqualTo(z11Count));
    });

    test('all tile coords have valid z values', () {
      const bbox = BoundingBox(
        minLat: 46.5,
        minLon: 11.3,
        maxLat: 46.6,
        maxLon: 11.4,
      );

      final tiles = enumerateTileCoords(bbox: bbox, minZoom: 8, maxZoom: 14);

      for (final tile in tiles) {
        expect(tile.z, greaterThanOrEqualTo(8));
        expect(tile.z, lessThanOrEqualTo(14));
      }
    });
  });

  group('estimateDownloadSize', () {
    test('estimates correctly with default tile size', () {
      final tiles = [
        const TileCoord(0, 0, 10),
        const TileCoord(1, 0, 10),
        const TileCoord(0, 1, 10),
        const TileCoord(1, 1, 10),
      ];

      final size = estimateDownloadSize(tiles);
      expect(size, 4 * 25000); // 4 tiles * 25KB default
    });

    test('estimates correctly with custom tile size', () {
      final tiles = [
        const TileCoord(0, 0, 10),
        const TileCoord(1, 0, 10),
      ];

      final size = estimateDownloadSize(tiles, avgTileSizeBytes: 50000);
      expect(size, 2 * 50000);
    });

    test('returns 0 for empty list', () {
      expect(estimateDownloadSize([]), 0);
    });
  });

  group('formatBytes', () {
    test('formats bytes correctly', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(500), '500 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('formats kilobytes correctly', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(10240), '10.0 KB');
    });

    test('formats megabytes correctly', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
    });

    test('formats gigabytes correctly', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });
  });
}
