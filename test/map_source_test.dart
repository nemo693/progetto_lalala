import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/models/map_source.dart';

void main() {
  group('MapSource', () {
    test('all contains exactly 7 sources', () {
      expect(MapSource.all.length, 7);
    });

    test('byId returns correct source', () {
      expect(MapSource.byId('openfree').name, 'OpenFreeMap');
      expect(MapSource.byId('opentopo').name, 'OpenTopoMap');
      expect(MapSource.byId('esri_imagery').name, 'Satellite');
    });

    test('byId returns default for unknown id', () {
      expect(MapSource.byId('nonexistent').id, 'openfree');
    });

    test('all source ids are unique', () {
      final ids = MapSource.all.map((s) => s.id).toSet();
      expect(ids.length, MapSource.all.length);
    });

    test('vector source styleString returns URL directly', () {
      expect(
        MapSource.openFreeMap.styleString,
        'https://tiles.openfreemap.org/styles/bright',
      );
    });

    test('raster source styleString returns valid JSON', () {
      final style = MapSource.openTopoMap.styleString;
      final decoded = jsonDecode(style) as Map<String, dynamic>;
      expect(decoded['version'], 8);
      expect(decoded['name'], 'OpenTopoMap');
      expect(decoded['sources'], isNotNull);
      expect(decoded['layers'], isList);

      final sources = decoded['sources'] as Map<String, dynamic>;
      final rasterSource = sources['raster-tiles'] as Map<String, dynamic>;
      expect(rasterSource['type'], 'raster');
      expect(rasterSource['tileSize'], 256);

      final tiles = rasterSource['tiles'] as List;
      expect(tiles.first, contains('opentopomap.org'));
    });

    test('Esri tile URL uses z/y/x order', () {
      final style = MapSource.esriWorldImagery.styleString;
      final decoded = jsonDecode(style) as Map<String, dynamic>;
      final sources = decoded['sources'] as Map<String, dynamic>;
      final tiles =
          (sources['raster-tiles'] as Map<String, dynamic>)['tiles'] as List;
      expect(tiles.first as String, contains('{z}/{y}/{x}'));
    });

    test('raster style JSON has exactly one layer', () {
      final style = MapSource.openTopoMap.styleString;
      final decoded = jsonDecode(style) as Map<String, dynamic>;
      final layers = decoded['layers'] as List;
      expect(layers.length, 1);
      expect((layers.first as Map<String, dynamic>)['type'], 'raster');
    });

    test('each source has non-empty attribution', () {
      for (final source in MapSource.all) {
        expect(source.attribution, isNotEmpty);
      }
    });

    test('avgTileSizeBytes is positive for all sources', () {
      for (final source in MapSource.all) {
        expect(source.avgTileSizeBytes, greaterThan(0));
      }
    });
  });

  group('Terrain analysis sources', () {
    test('slopeAnalysis is rasterXyz type', () {
      expect(MapSource.slopeAnalysis.type, MapSourceType.rasterXyz);
    });

    test('aspectAnalysis is rasterXyz type', () {
      expect(MapSource.aspectAnalysis.type, MapSourceType.rasterXyz);
    });

    test('slopeAnalysis has slope in id', () {
      expect(MapSource.slopeAnalysis.id, contains('slope'));
    });

    test('terrain sources are in all list', () {
      expect(MapSource.all.contains(MapSource.slopeAnalysis), true);
      expect(MapSource.all.contains(MapSource.aspectAnalysis), true);
    });

    test('terrain sources need computation flag', () {
      expect(MapSource.slopeAnalysis.needsComputation, true);
      expect(MapSource.aspectAnalysis.needsComputation, true);
      expect(MapSource.openFreeMap.needsComputation, false);
    });

    test('terrainStyleString produces valid JSON with file:// URL', () {
      final style = MapSource.slopeAnalysis.terrainStyleString('/data/app');
      final decoded = jsonDecode(style) as Map<String, dynamic>;
      expect(decoded['version'], 8);
      expect(decoded['name'], 'Slope Analysis');

      final sources = decoded['sources'] as Map<String, dynamic>;
      final raster = sources['raster-tiles'] as Map<String, dynamic>;
      final tiles = raster['tiles'] as List;
      expect(tiles.first as String,
          contains('file:///data/app/terrain_analysis/slope/'));
    });

    test('aspectAnalysis terrainStyleString uses aspect layer path', () {
      final style = MapSource.aspectAnalysis.terrainStyleString('/data/app');
      final decoded = jsonDecode(style) as Map<String, dynamic>;
      final sources = decoded['sources'] as Map<String, dynamic>;
      final raster = sources['raster-tiles'] as Map<String, dynamic>;
      final tiles = raster['tiles'] as List;
      expect(tiles.first as String,
          contains('terrain_analysis/aspect/'));
    });
  });
}
