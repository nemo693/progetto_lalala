import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/models/map_source.dart';

void main() {
  group('MapSource', () {
    test('all contains exactly 3 sources', () {
      expect(MapSource.all.length, 3);
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
}
