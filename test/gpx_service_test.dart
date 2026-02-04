import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/gpx_service.dart';
import 'package:alpinenav/models/route.dart';

// Minimal valid GPX with a track and waypoints
const _sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <metadata><name>Test Hike</name></metadata>
  <wpt lat="46.5" lon="11.35">
    <ele>2500</ele>
    <name>Summit</name>
    <sym>Peak</sym>
  </wpt>
  <wpt lat="46.49" lon="11.34">
    <name>Parking</name>
    <sym>Parking Area</sym>
  </wpt>
  <trk>
    <name>Approach</name>
    <trkseg>
      <trkpt lat="46.49" lon="11.34"><ele>1200</ele><time>2025-06-15T08:00:00Z</time></trkpt>
      <trkpt lat="46.495" lon="11.345"><ele>1500</ele><time>2025-06-15T09:00:00Z</time></trkpt>
      <trkpt lat="46.5" lon="11.35"><ele>2500</ele><time>2025-06-15T11:00:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

// GPX with only a <rte> element
const _routeGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <rte>
    <name>Via Ferrata</name>
    <rtept lat="46.0" lon="11.0"><ele>800</ele></rtept>
    <rtept lat="46.01" lon="11.01"><ele>1200</ele></rtept>
  </rte>
</gpx>''';

void main() {
  final service = GpxService();

  group('GpxService.importFromString', () {
    test('parses track points correctly', () async {
      final result = await service.importFromString(_sampleGpx);
      final route = result.route;

      expect(route.name, 'Approach');
      expect(route.points.length, 3);
      expect(route.points.first.latitude, 46.49);
      expect(route.points.first.elevation, 1200);
      expect(route.points.last.elevation, 2500);
    });

    test('computes stats from track', () async {
      final result = await service.importFromString(_sampleGpx);
      final route = result.route;

      expect(route.distance, greaterThan(0));
      expect(route.elevationGain, 1300); // 1200 → 1500 → 2500 = +1300
      expect(route.elevationLoss, 0);
      expect(route.duration.inHours, 3); // 08:00 to 11:00
    });

    test('extracts waypoints with symbols', () async {
      final result = await service.importFromString(_sampleGpx);
      final wpts = result.waypoints;

      expect(wpts.length, 2);
      expect(wpts[0].name, 'Summit');
      expect(wpts[0].symbol, 'summit'); // mapped from 'Peak'
      expect(wpts[0].elevation, 2500);
      expect(wpts[1].name, 'Parking');
      expect(wpts[1].symbol, 'parking'); // mapped from 'Parking Area'
    });

    test('parses <rte> elements', () async {
      final result = await service.importFromString(_routeGpx);
      final route = result.route;

      expect(route.name, 'Via Ferrata');
      expect(route.points.length, 2);
      expect(route.elevationGain, 400);
    });

    test('uses fallback name when GPX has none', () async {
      const bare = '''<?xml version="1.0"?><gpx version="1.1">
        <trk><trkseg>
          <trkpt lat="46.0" lon="11.0"/>
          <trkpt lat="46.1" lon="11.1"/>
        </trkseg></trk>
      </gpx>''';
      final result = await service.importFromString(bare, fallbackName: 'MyFallback');
      expect(result.route.name, 'MyFallback');
    });

    test('source is imported', () async {
      final result = await service.importFromString(_sampleGpx);
      expect(result.route.source, RouteSource.imported);
    });
  });

  group('GpxService.exportToString', () {
    test('round-trips a route through export and re-import', () async {
      final original = await service.importFromString(_sampleGpx);
      final exported = service.exportToString(original.route, original.waypoints);

      // Re-import the exported GPX
      final reimported = await service.importFromString(exported);

      expect(reimported.route.points.length, original.route.points.length);
      expect(reimported.waypoints.length, original.waypoints.length);
      expect(reimported.route.name, original.route.name);

      // Distances should match (within floating-point tolerance)
      expect(
        reimported.route.distance,
        closeTo(original.route.distance, 1.0),
      );
    });
  });
}
