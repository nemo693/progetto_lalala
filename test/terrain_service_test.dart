import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alpinenav/services/terrain_service.dart';

void main() {
  group('TerrainService.decodeTerrarium', () {
    test('decodes known RGB values to elevation', () {
      // Terrarium: elevation = (R * 256 + G + B / 256) - 32768
      // For sea level (0m): R=128, G=0, B=0 -> (128*256 + 0 + 0) - 32768 = 0
      expect(TerrainService.terrariumToElevation(128, 0, 0), closeTo(0.0, 0.1));

      // For 1000m: (R*256 + G + B/256) = 33768
      // R = 33768 ~/ 256 = 131, G = 33768 % 256 = 232, B = 0
      // elevation = (131*256 + 232 + 0) - 32768 = 33768 - 32768 = 1000
      expect(TerrainService.terrariumToElevation(131, 232, 0), closeTo(1000.0, 0.5));

      // For 3000m: 35768 -> R=139, G=184, B=0
      expect(TerrainService.terrariumToElevation(139, 184, 0), closeTo(3000.0, 0.5));
    });

    test('decodes RGBA bytes to elevation grid', () {
      // 2x2 grid of pixels, all at sea level (R=128, G=0, B=0, A=255)
      final rgba = Uint8List.fromList([
        128, 0, 0, 255, 128, 0, 0, 255,
        128, 0, 0, 255, 128, 0, 0, 255,
      ]);
      final grid = TerrainService.decodeTerrarium(rgba, 2, 2);
      expect(grid.length, 4); // 2x2
      expect(grid[0], closeTo(0.0, 0.1));
      expect(grid[3], closeTo(0.0, 0.1));
    });
  });

  group('TerrainService.computeSlope', () {
    test('returns zero slope for flat terrain', () {
      // 3x3 grid, all at 1000m
      final elevation = Float64List.fromList([
        1000, 1000, 1000,
        1000, 1000, 1000,
        1000, 1000, 1000,
      ]);
      final slope = TerrainService.computeSlope(elevation, 3, 3, cellSize: 30.0);
      // Center pixel should be 0 degrees
      expect(slope[4], closeTo(0.0, 0.1));
    });

    test('computes non-zero slope for tilted terrain', () {
      // 3x3 grid with 30m cell size, rising 30m south-to-north
      final elevation = Float64List.fromList([
        1000, 1000, 1000,
        1015, 1015, 1015,
        1030, 1030, 1030,
      ]);

      final slope = TerrainService.computeSlope(elevation, 3, 3, cellSize: 30.0);
      // Center pixel: south-north gradient = (1000-1030)/(2*30) = -0.5
      // arctan(0.5) ~ 26.6 degrees
      expect(slope[4], greaterThan(20.0));
      expect(slope[4], lessThan(30.0));
    });
  });

  group('TerrainService.computeAspect', () {
    test('returns -1 for flat terrain', () {
      final elevation = Float64List.fromList([
        1000, 1000, 1000,
        1000, 1000, 1000,
        1000, 1000, 1000,
      ]);
      final aspect = TerrainService.computeAspect(elevation, 3, 3, cellSize: 30.0);
      expect(aspect[4], -1.0); // flat = no aspect
    });

    test('detects north-facing slope', () {
      // Higher in south, lower in north -> north-facing
      final elevation = Float64List.fromList([
        900,  900,  900,
        950,  950,  950,
        1000, 1000, 1000,
      ]);
      final aspect = TerrainService.computeAspect(elevation, 3, 3, cellSize: 30.0);
      // North-facing should be ~0 or ~360 degrees
      expect(aspect[4], anyOf(lessThan(45.0), greaterThan(315.0)));
    });
  });

  group('TerrainService.colorizeSlope', () {
    test('returns RGBA bytes of correct length', () {
      final slope = Float64List.fromList([0, 15, 30, 45]);
      final hillshade = Float64List.fromList([200, 150, 100, 50]);
      final rgba = TerrainService.colorizeSlope(slope, hillshade, 2, 2);
      expect(rgba.length, 2 * 2 * 4); // width * height * RGBA
    });

    test('gentle slope produces greenish pixels', () {
      final slope = Float64List.fromList([5, 5, 5, 5]);
      final hillshade = Float64List.fromList([200, 200, 200, 200]);
      final rgba = TerrainService.colorizeSlope(slope, hillshade, 2, 2);
      // First pixel: R, G, B, A
      // Green channel should dominate for gentle slopes
      expect(rgba[1], greaterThan(rgba[0])); // G > R
    });
  });

  group('TerrainService.computeHillshade', () {
    test('returns values in 0-255 range', () {
      final elevation = Float64List.fromList([
        1000, 1010, 1020,
        1000, 1010, 1020,
        1000, 1010, 1020,
      ]);
      final hs = TerrainService.computeHillshade(elevation, 3, 3, cellSize: 30.0);
      for (final v in hs) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(255));
      }
    });
  });
}
