import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/offline_manager.dart';
import 'package:alpinenav/utils/tile_calculator.dart';

void main() {
  group('DownloadProgress', () {
    test('calculates progressPercent correctly', () {
      const progress = DownloadProgress(
        tilesDownloaded: 50,
        tilesTotal: 100,
        bytesDownloaded: 1250000,
      );
      expect(progress.progressPercent, 0.5);
    });

    test('progressPercent returns 0 for empty total', () {
      const progress = DownloadProgress(
        tilesDownloaded: 0,
        tilesTotal: 0,
        bytesDownloaded: 0,
      );
      expect(progress.progressPercent, 0.0);
    });

    test('toString formats correctly', () {
      const progress = DownloadProgress(
        tilesDownloaded: 25,
        tilesTotal: 100,
        bytesDownloaded: 625000,
      );
      final str = progress.toString();
      expect(str, contains('25/100'));
      expect(str, contains('KB'));
    });

    test('isComplete defaults to false', () {
      const progress = DownloadProgress(
        tilesDownloaded: 100,
        tilesTotal: 100,
        bytesDownloaded: 2500000,
      );
      expect(progress.isComplete, false);
    });

    test('error field is nullable', () {
      const progress = DownloadProgress(
        tilesDownloaded: 0,
        tilesTotal: 100,
        bytesDownloaded: 0,
        isComplete: true,
        error: 'Network error',
      );
      expect(progress.error, 'Network error');
    });
  });

  group('OfflineRegion', () {
    test('serializes to JSON and back', () {
      final region = OfflineRegion(
        id: 'test-123',
        name: 'Dolomites Winter 2025',
        bounds: const BoundingBox(
          minLat: 46.0,
          minLon: 11.0,
          maxLat: 47.0,
          maxLon: 12.5,
        ),
        minZoom: 8,
        maxZoom: 14,
        tileCount: 5000,
        sizeBytes: 125000000,
        createdAt: DateTime.utc(2025, 1, 15, 10, 30),
      );

      final json = region.toJson();
      final restored = OfflineRegion.fromJson(json);

      expect(restored.id, region.id);
      expect(restored.name, region.name);
      expect(restored.bounds.minLat, region.bounds.minLat);
      expect(restored.bounds.maxLat, region.bounds.maxLat);
      expect(restored.bounds.minLon, region.bounds.minLon);
      expect(restored.bounds.maxLon, region.bounds.maxLon);
      expect(restored.minZoom, region.minZoom);
      expect(restored.maxZoom, region.maxZoom);
      expect(restored.tileCount, region.tileCount);
      expect(restored.sizeBytes, region.sizeBytes);
      expect(restored.createdAt, region.createdAt);
    });

    test('JSON contains all required fields', () {
      final region = OfflineRegion(
        id: 'r1',
        name: 'Test',
        bounds: const BoundingBox(
          minLat: 46.0,
          minLon: 11.0,
          maxLat: 47.0,
          maxLon: 12.0,
        ),
        minZoom: 10,
        maxZoom: 12,
        tileCount: 100,
        sizeBytes: 2500000,
        createdAt: DateTime.utc(2025, 6, 1),
      );

      final json = region.toJson();

      expect(json.containsKey('id'), true);
      expect(json.containsKey('name'), true);
      expect(json.containsKey('minLat'), true);
      expect(json.containsKey('minLon'), true);
      expect(json.containsKey('maxLat'), true);
      expect(json.containsKey('maxLon'), true);
      expect(json.containsKey('minZoom'), true);
      expect(json.containsKey('maxZoom'), true);
      expect(json.containsKey('tileCount'), true);
      expect(json.containsKey('sizeBytes'), true);
      expect(json.containsKey('createdAt'), true);
    });
  });

  group('OfflineManager instantiation', () {
    test('can be instantiated', () {
      final manager = OfflineManager();
      expect(manager, isNotNull);
    });
  });
}
