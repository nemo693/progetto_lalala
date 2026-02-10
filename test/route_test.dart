import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/models/route.dart';

void main() {
  group('TrackPoint', () {
    test('serializes to JSON and back', () {
      final tp = TrackPoint(
        latitude: 46.5,
        longitude: 11.35,
        elevation: 1200.5,
        timestamp: DateTime.utc(2025, 6, 15, 10, 30),
      );
      final json = tp.toJson();
      final restored = TrackPoint.fromJson(json);

      expect(restored.latitude, tp.latitude);
      expect(restored.longitude, tp.longitude);
      expect(restored.elevation, tp.elevation);
      expect(restored.timestamp, tp.timestamp);
    });

    test('handles null elevation and timestamp', () {
      final tp = TrackPoint(latitude: 46.0, longitude: 11.0);
      final json = tp.toJson();
      expect(json.containsKey('ele'), false);
      expect(json.containsKey('time'), false);

      final restored = TrackPoint.fromJson(json);
      expect(restored.elevation, isNull);
      expect(restored.timestamp, isNull);
    });
  });

  group('RouteStats', () {
    test('returns zeros for empty or single-point list', () {
      final stats0 = RouteStats.compute([]);
      expect(stats0.distance, 0);
      expect(stats0.elevationGain, 0);
      expect(stats0.minElevation, isNull);
      expect(stats0.maxElevation, isNull);

      final stats1 = RouteStats.compute([
        TrackPoint(latitude: 46.0, longitude: 11.0),
      ]);
      expect(stats1.distance, 0);
      expect(stats1.minElevation, isNull);
      expect(stats1.maxElevation, isNull);

      // Single point WITH elevation should report it
      final stats2 = RouteStats.compute([
        TrackPoint(latitude: 46.0, longitude: 11.0, elevation: 1500),
      ]);
      expect(stats2.distance, 0);
      expect(stats2.minElevation, 1500);
      expect(stats2.maxElevation, 1500);
    });

    test('computes distance between two known points', () {
      // Bolzano (46.4983, 11.3548) to Trento (46.0679, 11.1211)
      // ~ 49 km straight line
      final points = [
        TrackPoint(latitude: 46.4983, longitude: 11.3548),
        TrackPoint(latitude: 46.0679, longitude: 11.1211),
      ];
      final stats = RouteStats.compute(points);
      // Should be roughly 49-51 km
      expect(stats.distance, greaterThan(47000));
      expect(stats.distance, lessThan(52000));
    });

    test('computes elevation gain and loss', () {
      final points = [
        TrackPoint(latitude: 46.0, longitude: 11.0, elevation: 1000),
        TrackPoint(latitude: 46.001, longitude: 11.0, elevation: 1200),
        TrackPoint(latitude: 46.002, longitude: 11.0, elevation: 1150),
        TrackPoint(latitude: 46.003, longitude: 11.0, elevation: 1400),
      ];
      final stats = RouteStats.compute(points);
      expect(stats.elevationGain, 450); // +200 + 250
      expect(stats.elevationLoss, 50); // -50
      expect(stats.minElevation, 1000);
      expect(stats.maxElevation, 1400);
    });

    test('minElevation/maxElevation are null when no points have elevation', () {
      final points = [
        TrackPoint(latitude: 46.0, longitude: 11.0),
        TrackPoint(latitude: 46.01, longitude: 11.0),
      ];
      final stats = RouteStats.compute(points);
      expect(stats.minElevation, isNull);
      expect(stats.maxElevation, isNull);
    });

    test('computes duration from timestamps', () {
      final start = DateTime.utc(2025, 6, 15, 8, 0);
      final end = DateTime.utc(2025, 6, 15, 10, 30);
      final points = [
        TrackPoint(latitude: 46.0, longitude: 11.0, timestamp: start),
        TrackPoint(latitude: 46.1, longitude: 11.0, timestamp: end),
      ];
      final stats = RouteStats.compute(points);
      expect(stats.duration.inMinutes, 150);
    });
  });

  group('NavRoute', () {
    test('fromPoints computes stats automatically', () {
      final points = [
        TrackPoint(latitude: 46.0, longitude: 11.0, elevation: 1000),
        TrackPoint(latitude: 46.01, longitude: 11.0, elevation: 1100),
        TrackPoint(latitude: 46.02, longitude: 11.0, elevation: 1050),
      ];

      final route = NavRoute.fromPoints(
        id: 'test-1',
        name: 'Test Route',
        points: points,
        source: RouteSource.imported,
      );

      expect(route.id, 'test-1');
      expect(route.name, 'Test Route');
      expect(route.points.length, 3);
      expect(route.distance, greaterThan(0));
      expect(route.elevationGain, 100);
      expect(route.elevationLoss, 50);
      expect(route.minElevation, 1000);
      expect(route.maxElevation, 1100);
      expect(route.source, RouteSource.imported);
    });

    test('coordinatePairs returns correct format', () {
      final route = NavRoute.fromPoints(
        id: '1',
        name: 'R',
        points: [
          TrackPoint(latitude: 46.0, longitude: 11.0),
          TrackPoint(latitude: 46.1, longitude: 11.1),
        ],
        source: RouteSource.recorded,
      );

      final pairs = route.coordinatePairs;
      expect(pairs.length, 2);
      expect(pairs[0], [46.0, 11.0]);
      expect(pairs[1], [46.1, 11.1]);
    });
  });
}
