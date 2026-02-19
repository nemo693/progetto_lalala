import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/terrain_tile_manager.dart';
import 'package:alpinenav/utils/tile_calculator.dart';

void main() {
  group('TerrainTileManager', () {
    test('terrariumUrl builds correct URL', () {
      final url = TerrainTileManager.terrariumUrl(12, 2176, 1456);
      expect(url, 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/2176/1456.png');
    });

    test('outputPath builds correct cache path', () {
      final path = TerrainTileManager.outputPath('/cache', 'slope', 12, 2176, 1456);
      expect(path, '/cache/terrain_analysis/slope/12/2176/1456.png');
    });

    test('estimateTerrainTiles returns correct count for single zoom', () {
      const bbox = BoundingBox(
        minLat: 46.5, minLon: 11.3, maxLat: 46.6, maxLon: 11.4,
      );
      final tiles = TerrainTileManager.enumerateTerrainTiles(bbox, zoom: 12);
      expect(tiles, isNotEmpty);
      // All tiles should be at zoom 12
      for (final t in tiles) {
        expect(t.z, 12);
      }
    });

    test('TerrainProgress reports fields correctly', () {
      const p = TerrainProgress(
        phase: TerrainPhase.downloading,
        current: 5,
        total: 20,
        layer: 'slope',
      );
      expect(p.fraction, closeTo(0.25, 0.01));
      expect(p.isComplete, false);
    });

    test('TerrainProgress isComplete when current == total and phase is done', () {
      const p = TerrainProgress(
        phase: TerrainPhase.done,
        current: 20,
        total: 20,
        layer: 'slope',
      );
      expect(p.isComplete, true);
    });
  });
}
