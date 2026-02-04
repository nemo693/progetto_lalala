import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/models/waypoint.dart';

void main() {
  group('Waypoint', () {
    test('serializes to JSON and back', () {
      final wpt = Waypoint(
        id: 'wpt-1',
        name: 'Summit',
        description: 'High point',
        latitude: 46.5,
        longitude: 11.35,
        elevation: 3000.0,
        symbol: 'summit',
        routeId: 'route-1',
        createdAt: DateTime.utc(2025, 6, 15),
      );

      final json = wpt.toJson();
      final restored = Waypoint.fromJson(json);

      expect(restored.id, 'wpt-1');
      expect(restored.name, 'Summit');
      expect(restored.description, 'High point');
      expect(restored.latitude, 46.5);
      expect(restored.longitude, 11.35);
      expect(restored.elevation, 3000.0);
      expect(restored.symbol, 'summit');
      expect(restored.routeId, 'route-1');
    });

    test('handles nullable fields', () {
      final wpt = Waypoint(
        id: 'wpt-2',
        name: 'Point',
        latitude: 46.0,
        longitude: 11.0,
        createdAt: DateTime.utc(2025, 1, 1),
      );

      final json = wpt.toJson();
      expect(json.containsKey('desc'), false);
      expect(json.containsKey('ele'), false);
      expect(json.containsKey('routeId'), false);

      final restored = Waypoint.fromJson(json);
      expect(restored.description, isNull);
      expect(restored.elevation, isNull);
      expect(restored.routeId, isNull);
      expect(restored.symbol, 'generic');
    });
  });
}
