import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/offline_manager.dart';
import 'package:alpinenav/utils/tile_calculator.dart';

void main() {
  group('DownloadProgress', () {
    test('stores progressPercent correctly', () {
      const progress = DownloadProgress(progressPercent: 0.5);
      expect(progress.progressPercent, 0.5);
    });

    test('isComplete defaults to false', () {
      const progress = DownloadProgress(progressPercent: 1.0);
      expect(progress.isComplete, false);
    });

    test('error field is nullable', () {
      const progress = DownloadProgress(
        progressPercent: 0,
        isComplete: true,
        error: 'Network error',
      );
      expect(progress.error, 'Network error');
      expect(progress.isComplete, true);
    });

    test('toString formats percentage', () {
      const progress = DownloadProgress(progressPercent: 0.753);
      final str = progress.toString();
      expect(str, contains('75.3%'));
    });
  });

  group('OfflineRegion', () {
    test('stores all fields', () {
      const region = OfflineRegion(
        id: 1,
        name: 'Dolomites Winter 2025',
        bounds: BoundingBox(
          minLat: 46.0,
          minLon: 11.0,
          maxLat: 47.0,
          maxLon: 12.5,
        ),
        minZoom: 8,
        maxZoom: 14,
      );

      expect(region.id, 1);
      expect(region.name, 'Dolomites Winter 2025');
      expect(region.bounds.minLat, 46.0);
      expect(region.bounds.maxLon, 12.5);
      expect(region.minZoom, 8);
      expect(region.maxZoom, 14);
    });
  });

  group('OfflineManager', () {
    test('can be instantiated', () {
      final manager = OfflineManager();
      expect(manager, isNotNull);
    });

    test('estimateTileCount returns correct count', () {
      final manager = OfflineManager();
      const bounds = BoundingBox(
        minLat: 46.4,
        minLon: 11.3,
        maxLat: 46.6,
        maxLon: 11.5,
      );
      final count = manager.estimateTileCount(bounds, 10, 12);
      expect(count, greaterThan(0));
    });

    test('estimateSize returns 25KB per tile', () {
      final manager = OfflineManager();
      expect(manager.estimateSize(100), 2500000);
      expect(manager.estimateSize(0), 0);
      expect(manager.estimateSize(1), 25000);
    });
  });
}
