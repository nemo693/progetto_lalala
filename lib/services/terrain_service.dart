import 'dart:math';
import 'dart:typed_data';

/// Pure computation functions for terrain analysis.
///
/// Decodes AWS Terrarium elevation tiles, computes slope/aspect/hillshade,
/// and colorizes results. All functions are pure (no I/O, no Flutter deps)
/// so they can run in isolates.
class TerrainService {
  // -- Terrarium decoding ---------------------------------------------------

  /// Decode a single Terrarium pixel to elevation in meters.
  ///
  /// Terrarium encoding: elevation = (R * 256 + G + B / 256) - 32768
  static double terrariumToElevation(int r, int g, int b) {
    return (r * 256.0 + g + b / 256.0) - 32768.0;
  }

  /// Decode RGBA pixel bytes into a flat elevation grid (row-major).
  ///
  /// [rgba] contains 4 bytes per pixel: R, G, B, A.
  /// Returns a Float64List of length [width] * [height].
  static Float64List decodeTerrarium(Uint8List rgba, int width, int height) {
    final grid = Float64List(width * height);
    for (int i = 0; i < width * height; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      grid[i] = terrariumToElevation(r, g, b);
    }
    return grid;
  }

  // -- Slope computation ----------------------------------------------------

  /// Compute slope in degrees for each pixel using Horn's method.
  ///
  /// [elevation] is a flat grid of [width] x [height] elevations.
  /// [cellSize] is the ground distance per pixel in meters.
  /// Edge pixels are set to 0.
  ///
  /// Returns Float64List of slope in degrees (0-90).
  static Float64List computeSlope(
    Float64List elevation,
    int width,
    int height, {
    required double cellSize,
  }) {
    final slope = Float64List(width * height);

    for (int row = 1; row < height - 1; row++) {
      for (int col = 1; col < width - 1; col++) {
        final idx = row * width + col;

        // 3x3 neighborhood
        final nw = elevation[(row - 1) * width + (col - 1)];
        final n  = elevation[(row - 1) * width + col];
        final ne = elevation[(row - 1) * width + (col + 1)];
        final w  = elevation[row * width + (col - 1)];
        final e  = elevation[row * width + (col + 1)];
        final sw = elevation[(row + 1) * width + (col - 1)];
        final s  = elevation[(row + 1) * width + col];
        final se = elevation[(row + 1) * width + (col + 1)];

        // Horn's method (same as GDAL gdaldem slope)
        final dzdx = ((ne + 2 * e + se) - (nw + 2 * w + sw)) / (8 * cellSize);
        final dzdy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) / (8 * cellSize);

        slope[idx] = atan(sqrt(dzdx * dzdx + dzdy * dzdy)) * 180.0 / pi;
      }
    }

    return slope;
  }

  // -- Aspect computation ---------------------------------------------------

  /// Compute aspect in degrees (0=N, 90=E, 180=S, 270=W, -1=flat).
  ///
  /// Same neighborhood and gradient as slope.
  static Float64List computeAspect(
    Float64List elevation,
    int width,
    int height, {
    required double cellSize,
    double flatThreshold = 1.0,
  }) {
    final aspect = Float64List(width * height);
    // Initialize to -1 (flat)
    for (int i = 0; i < aspect.length; i++) {
      aspect[i] = -1.0;
    }

    for (int row = 1; row < height - 1; row++) {
      for (int col = 1; col < width - 1; col++) {
        final idx = row * width + col;

        final nw = elevation[(row - 1) * width + (col - 1)];
        final n  = elevation[(row - 1) * width + col];
        final ne = elevation[(row - 1) * width + (col + 1)];
        final w  = elevation[row * width + (col - 1)];
        final e  = elevation[row * width + (col + 1)];
        final sw = elevation[(row + 1) * width + (col - 1)];
        final s  = elevation[(row + 1) * width + col];
        final se = elevation[(row + 1) * width + (col + 1)];

        final dzdx = ((ne + 2 * e + se) - (nw + 2 * w + sw)) / (8 * cellSize);
        final dzdy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) / (8 * cellSize);

        final slopeRad = atan(sqrt(dzdx * dzdx + dzdy * dzdy));
        final slopeDeg = slopeRad * 180.0 / pi;

        if (slopeDeg < flatThreshold) {
          aspect[idx] = -1.0;
          continue;
        }

        // Aspect = direction the slope faces (downhill direction).
        // In our grid: row increases southward, col increases eastward.
        // dzdy > 0 means elevation increases southward → slope faces north.
        // dzdx > 0 means elevation increases eastward → slope faces west.
        // atan2(-dzdx, dzdy) gives clockwise angle from north.
        var a = atan2(-dzdx, dzdy) * 180.0 / pi;
        a = (a + 360) % 360;
        aspect[idx] = a;
      }
    }

    return aspect;
  }

  // -- Hillshade ------------------------------------------------------------

  /// Compute hillshade illumination (0-255).
  ///
  /// Default: azimuth 315 (NW), altitude 45 degrees — standard cartographic
  /// lighting. Used to blend with slope/aspect colors for legibility.
  static Float64List computeHillshade(
    Float64List elevation,
    int width,
    int height, {
    required double cellSize,
    double azimuthDeg = 315.0,
    double altitudeDeg = 45.0,
  }) {
    final hs = Float64List(width * height);

    final azRad = azimuthDeg * pi / 180.0;
    final altRad = altitudeDeg * pi / 180.0;

    for (int row = 1; row < height - 1; row++) {
      for (int col = 1; col < width - 1; col++) {
        final idx = row * width + col;

        final nw = elevation[(row - 1) * width + (col - 1)];
        final n  = elevation[(row - 1) * width + col];
        final ne = elevation[(row - 1) * width + (col + 1)];
        final w  = elevation[row * width + (col - 1)];
        final e  = elevation[row * width + (col + 1)];
        final sw = elevation[(row + 1) * width + (col - 1)];
        final s  = elevation[(row + 1) * width + col];
        final se = elevation[(row + 1) * width + (col + 1)];

        final dzdx = ((ne + 2 * e + se) - (nw + 2 * w + sw)) / (8 * cellSize);
        final dzdy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) / (8 * cellSize);

        final slopeRad = atan(sqrt(dzdx * dzdx + dzdy * dzdy));
        final aspectRad = atan2(-dzdy, -dzdx);

        // Standard hillshade formula
        var illumination = sin(altRad) * cos(slopeRad) +
            cos(altRad) * sin(slopeRad) * cos(azRad - aspectRad);

        hs[idx] = (illumination.clamp(0.0, 1.0) * 255.0);
      }
    }

    // Edge pixels: neutral gray
    for (int col = 0; col < width; col++) {
      hs[col] = 180.0; // top row
      hs[(height - 1) * width + col] = 180.0; // bottom row
    }
    for (int row = 0; row < height; row++) {
      hs[row * width] = 180.0; // left col
      hs[row * width + (width - 1)] = 180.0; // right col
    }

    return hs;
  }

  // -- Colorization ---------------------------------------------------------

  /// Colorize slope with ski-touring color scheme, blended with hillshade.
  ///
  /// Color bins (degrees):
  ///   0-27: green (safe touring terrain)
  ///   27-30: yellow (critical avalanche angle)
  ///   30-35: orange (very steep, high avalanche risk)
  ///   35-45: red (extreme)
  ///   45+: dark red (cliff/rock)
  ///
  /// Returns RGBA Uint8List of length width*height*4.
  static Uint8List colorizeSlope(
    Float64List slope,
    Float64List hillshade,
    int width,
    int height, {
    double hillshadeBlend = 0.35,
  }) {
    final rgba = Uint8List(width * height * 4);

    for (int i = 0; i < width * height; i++) {
      final s = slope[i];
      final hs = hillshade[i] / 255.0; // normalize to 0-1

      // Base color from slope bins
      int r, g, b;
      if (s < 27) {
        // Green — safe ski touring
        r = 76; g = 175; b = 80;
      } else if (s < 30) {
        // Yellow — critical 27-30 degree band
        r = 255; g = 235; b = 59;
      } else if (s < 35) {
        // Orange — steep, high risk
        r = 255; g = 152; b = 0;
      } else if (s < 45) {
        // Red — extreme
        r = 244; g = 67; b = 54;
      } else {
        // Dark red — cliff/rock
        r = 139; g = 0; b = 0;
      }

      // Blend with hillshade for terrain relief visibility
      final blend = 1.0 - hillshadeBlend + hillshadeBlend * hs;
      rgba[i * 4]     = (r * blend).round().clamp(0, 255);
      rgba[i * 4 + 1] = (g * blend).round().clamp(0, 255);
      rgba[i * 4 + 2] = (b * blend).round().clamp(0, 255);
      rgba[i * 4 + 3] = 255; // fully opaque
    }

    return rgba;
  }

  /// Colorize aspect with a warm/cool scheme, blended with hillshade.
  ///
  /// Semantics for the Alps: south-facing = warm (sun, melt risk);
  /// north-facing = cold (shade, persistent snow, avalanche risk).
  ///
  ///   N:   deep blue     — cold, shaded, persistent snow
  ///   NE:  steel blue    — mostly shaded
  ///   E:   light blue-grey
  ///   SE:  warm beige    — morning sun, transitional
  ///   S:   warm amber    — sunny, high insolation
  ///   SW:  golden tan    — afternoon sun
  ///   W:   cool tan      — late sun, drier
  ///   NW:  muted slate   — mostly shaded
  ///   Flat: neutral grey
  ///
  /// Returns RGBA Uint8List of length width*height*4.
  static Uint8List colorizeAspect(
    Float64List aspect,
    Float64List hillshade,
    int width,
    int height, {
    double hillshadeBlend = 0.35,
  }) {
    final rgba = Uint8List(width * height * 4);

    for (int i = 0; i < width * height; i++) {
      final a = aspect[i];
      final hs = hillshade[i] / 255.0;

      int r, g, b;
      if (a < 0) {
        // Flat — neutral mid-grey
        r = 150; g = 150; b = 150;
      } else if (a < 22.5 || a >= 337.5) {
        // N — deep blue: cold, shaded
        r = 58; g = 90; b = 148;
      } else if (a < 67.5) {
        // NE — steel blue: mostly shaded
        r = 98; g = 138; b = 185;
      } else if (a < 112.5) {
        // E — light blue-grey: morning light
        r = 168; g = 195; b = 215;
      } else if (a < 157.5) {
        // SE — warm beige: transitional
        r = 215; g = 200; b = 170;
      } else if (a < 202.5) {
        // S — warm amber: sunny south-facing
        r = 220; g = 160; b = 60;
      } else if (a < 247.5) {
        // SW — golden tan: afternoon sun
        r = 195; g = 155; b = 90;
      } else if (a < 292.5) {
        // W — cool tan: late sun
        r = 160; g = 160; b = 130;
      } else {
        // NW — muted slate: mostly shaded
        r = 108; g = 120; b = 148;
      }

      final blend = 1.0 - hillshadeBlend + hillshadeBlend * hs;
      rgba[i * 4]     = (r * blend).round().clamp(0, 255);
      rgba[i * 4 + 1] = (g * blend).round().clamp(0, 255);
      rgba[i * 4 + 2] = (b * blend).round().clamp(0, 255);
      rgba[i * 4 + 3] = 255;
    }

    return rgba;
  }

  // -- Cell size calculation ------------------------------------------------

  /// Approximate ground resolution (meters/pixel) for a Terrarium tile.
  ///
  /// At the equator, zoom 0 = ~156km/pixel. At zoom 12 in the Alps (~46N),
  /// one 256px tile covers ~6.7km, so cellSize ~ 26m.
  static double cellSizeMeters(int zoom, double latitudeDeg) {
    const earthCircumference = 40075016.686; // meters
    final metersPerPixel =
        earthCircumference * cos(latitudeDeg * pi / 180.0) / (256 * (1 << zoom));
    return metersPerPixel;
  }
}
