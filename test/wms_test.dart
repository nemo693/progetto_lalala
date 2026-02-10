import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/utils/tile_calculator.dart';
import 'package:alpinenav/models/map_source.dart';

void main() {
  group('getTileEpsg3857BBox', () {
    test('tile 0/0/0 covers full Web Mercator extent', () {
      final bbox = getTileEpsg3857BBox(0, 0, 0);
      const originShift = 20037508.342789244;
      expect(bbox.minX, closeTo(-originShift, 0.01));
      expect(bbox.minY, closeTo(-originShift, 0.01));
      expect(bbox.maxX, closeTo(originShift, 0.01));
      expect(bbox.maxY, closeTo(originShift, 0.01));
    });

    test('zoom 1 tiles partition the world into 4 quadrants', () {
      // At zoom 1: 2x2 tiles
      final nw = getTileEpsg3857BBox(1, 0, 0);
      final ne = getTileEpsg3857BBox(1, 1, 0);
      final sw = getTileEpsg3857BBox(1, 0, 1);
      final se = getTileEpsg3857BBox(1, 1, 1);

      // NW: left half, top half
      expect(nw.minX, closeTo(-20037508.34, 1));
      expect(nw.maxX, closeTo(0, 1));
      expect(nw.minY, closeTo(0, 1));
      expect(nw.maxY, closeTo(20037508.34, 1));

      // SE: right half, bottom half
      expect(se.minX, closeTo(0, 1));
      expect(se.maxX, closeTo(20037508.34, 1));
      expect(se.minY, closeTo(-20037508.34, 1));
      expect(se.maxY, closeTo(0, 1));

      // NE and SW are the other two
      expect(ne.minX, closeTo(0, 1));
      expect(sw.maxX, closeTo(0, 1));
    });

    test('tiles at same zoom have equal dimensions', () {
      final a = getTileEpsg3857BBox(10, 100, 200);
      final b = getTileEpsg3857BBox(10, 300, 400);

      final widthA = a.maxX - a.minX;
      final widthB = b.maxX - b.minX;
      final heightA = a.maxY - a.minY;
      final heightB = b.maxY - b.minY;

      expect(widthA, closeTo(widthB, 0.01));
      expect(heightA, closeTo(heightB, 0.01));
    });

    test('higher zoom gives smaller tiles', () {
      final z10 = getTileEpsg3857BBox(10, 0, 0);
      final z15 = getTileEpsg3857BBox(15, 0, 0);

      final width10 = z10.maxX - z10.minX;
      final width15 = z15.maxX - z15.minX;

      // z15 tile should be 2^5 = 32 times smaller
      expect(width10 / width15, closeTo(32, 0.01));
    });

    test('Dolomites area tile bbox is reasonable', () {
      // Tile containing ~46.5N, 11.35E at zoom 14
      final x = lonToTileX(11.35, 14);
      final y = latToTileY(46.5, 14);
      final bbox = getTileEpsg3857BBox(14, x, y);

      // EPSG:3857 for 11.35E ≈ 1,263,000 m, 46.5N ≈ 5,870,000 m
      expect(bbox.minX, greaterThan(1200000));
      expect(bbox.maxX, lessThan(1300000));
      expect(bbox.minY, greaterThan(5800000));
      expect(bbox.maxY, lessThan(5900000));

      // Tile width at z14: ~2445 meters
      final width = bbox.maxX - bbox.minX;
      expect(width, closeTo(2445, 5));
    });
  });

  group('MapSource WMS', () {
    test('PCN source has correct type and fields', () {
      final pcn = MapSource.pcnOrthophoto;
      expect(pcn.type, MapSourceType.wms);
      expect(pcn.wmsBaseUrl, isNotNull);
      expect(pcn.wmsLayers, 'OI.ORTOIMMAGINI.2012.32,OI.ORTOIMMAGINI.2012.33');
      expect(pcn.wmsCrs, 'EPSG:3857');
      expect(pcn.wmsFormat, 'image/jpeg');
    });

    test('buildWmsGetMapUrl produces valid URL', () {
      final url = MapSource.pcnOrthophoto.buildWmsGetMapUrl(14, 8655, 5828);

      expect(url, contains('SERVICE=WMS'));
      expect(url, contains('VERSION=1.1.0'));
      expect(url, contains('REQUEST=GetMap'));
      expect(url, contains('LAYERS=OI.ORTOIMMAGINI.2012.32,OI.ORTOIMMAGINI.2012.33'));
      expect(url, contains('SRS=EPSG:3857'));
      expect(url, contains('WIDTH=256'));
      expect(url, contains('HEIGHT=256'));
      expect(url, contains('FORMAT=image/jpeg'));
      expect(url, contains('BBOX='));
      expect(url, contains('wms.pcn.minambiente.it'));
    });

    test('buildWmsGetMapUrl uses & separator when base has ?', () {
      final url = MapSource.pcnOrthophoto.buildWmsGetMapUrl(10, 540, 360);
      // PCN base URL already has ?map=... so separator should be &
      expect(url, contains('.map&SERVICE=WMS'));
    });

    test('all list contains WMS sources', () {
      expect(MapSource.all.where((s) => s.type == MapSourceType.wms), isNotEmpty);
    });

    test('byId finds WMS sources', () {
      final source = MapSource.byId('pcn_ortho');
      expect(source.id, 'pcn_ortho');
      expect(source.type, MapSourceType.wms);
    });

    test('WMS source styleString returns empty style (not for base map)', () {
      final style = MapSource.pcnOrthophoto.styleString;
      expect(style, contains('"sources":{}'));
    });

    test('WMS sources have non-empty attribution', () {
      for (final source in MapSource.all.where((s) => s.type == MapSourceType.wms)) {
        expect(source.attribution, isNotEmpty);
      }
    });

    test('WMS sources have positive avgTileSizeBytes', () {
      for (final source in MapSource.all.where((s) => s.type == MapSourceType.wms)) {
        expect(source.avgTileSizeBytes, greaterThan(0));
      }
    });
  });

  group('Tile estimate for WMS download', () {
    test('Dolomites area at z10-15 produces reasonable tile count', () {
      // Roughly 46.2-46.8 N, 11.0-11.7 E
      final tiles = enumerateTileCoords(
        bbox: const BoundingBox(
          minLat: 46.2,
          minLon: 11.0,
          maxLat: 46.8,
          maxLon: 11.7,
        ),
        minZoom: 10,
        maxZoom: 15,
      );
      // Should be in the hundreds to low thousands
      expect(tiles.length, greaterThan(100));
      expect(tiles.length, lessThan(10000));

      // Size estimate with PCN avg tile size
      final sizeBytes = estimateDownloadSize(
        tiles,
        avgTileSizeBytes: MapSource.pcnOrthophoto.avgTileSizeBytes,
      );
      // Roughly 6-600 MB
      expect(sizeBytes, greaterThan(1024 * 1024));
      expect(sizeBytes, lessThan(600 * 1024 * 1024));
    });
  });
}
