import 'dart:math' as math;

/// A single GPS track point with coordinates, elevation, and timestamp.
class TrackPoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? timestamp;

  const TrackPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        if (elevation != null) 'ele': elevation,
        if (timestamp != null) 'time': timestamp!.toIso8601String(),
      };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        elevation: json['ele'] != null ? (json['ele'] as num).toDouble() : null,
        timestamp:
            json['time'] != null ? DateTime.parse(json['time'] as String) : null,
      );
}

/// Route source: imported from a GPX file or recorded live.
enum RouteSource { imported, recorded }

/// A saved track or imported route with computed statistics.
class NavRoute {
  final String id;
  final String name;
  final String? description;
  final List<TrackPoint> points;
  final double distance; // meters
  final double elevationGain; // meters
  final double elevationLoss; // meters
  final double? minElevation; // meters
  final double? maxElevation; // meters
  final Duration duration;
  final RouteSource source;
  final DateTime createdAt;
  final String? filePath;

  const NavRoute({
    required this.id,
    required this.name,
    this.description,
    required this.points,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    this.minElevation,
    this.maxElevation,
    required this.duration,
    required this.source,
    required this.createdAt,
    this.filePath,
  });

  /// Create a NavRoute from a list of TrackPoints, computing stats automatically.
  factory NavRoute.fromPoints({
    required String id,
    required String name,
    String? description,
    required List<TrackPoint> points,
    required RouteSource source,
    String? filePath,
  }) {
    final stats = RouteStats.compute(points);
    return NavRoute(
      id: id,
      name: name,
      description: description,
      points: points,
      distance: stats.distance,
      elevationGain: stats.elevationGain,
      elevationLoss: stats.elevationLoss,
      minElevation: stats.minElevation,
      maxElevation: stats.maxElevation,
      duration: stats.duration,
      source: source,
      createdAt: DateTime.now(),
      filePath: filePath,
    );
  }

  /// Coordinate pairs as [lat, lon] for map display.
  List<List<double>> get coordinatePairs =>
      points.map((p) => [p.latitude, p.longitude]).toList();
}

/// Computed statistics for a list of track points.
class RouteStats {
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final double? minElevation;
  final double? maxElevation;
  final Duration duration;

  const RouteStats({
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    this.minElevation,
    this.maxElevation,
    required this.duration,
  });

  static RouteStats compute(List<TrackPoint> points) {
    if (points.isEmpty) {
      return const RouteStats(
        distance: 0,
        elevationGain: 0,
        elevationLoss: 0,
        duration: Duration.zero,
      );
    }

    if (points.length == 1) {
      return RouteStats(
        distance: 0,
        elevationGain: 0,
        elevationLoss: 0,
        minElevation: points.first.elevation,
        maxElevation: points.first.elevation,
        duration: Duration.zero,
      );
    }

    double totalDistance = 0;
    double gain = 0;
    double loss = 0;
    double? minEle;
    double? maxEle;

    for (int i = 1; i < points.length; i++) {
      totalDistance += _haversineMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );

      final prevEle = points[i - 1].elevation;
      final currEle = points[i].elevation;
      if (prevEle != null && currEle != null) {
        final diff = currEle - prevEle;
        if (diff > 0) {
          gain += diff;
        } else {
          loss += diff.abs();
        }
      }
    }

    // Compute min/max elevation from all points with elevation data
    for (final pt in points) {
      final ele = pt.elevation;
      if (ele != null) {
        minEle = minEle == null ? ele : math.min(minEle, ele);
        maxEle = maxEle == null ? ele : math.max(maxEle, ele);
      }
    }

    // Duration: time between first and last timestamped points
    Duration dur = Duration.zero;
    final firstTime = points.first.timestamp;
    final lastTime = points.last.timestamp;
    if (firstTime != null && lastTime != null) {
      dur = lastTime.difference(firstTime);
    }

    return RouteStats(
      distance: totalDistance,
      elevationGain: gain,
      elevationLoss: loss,
      minElevation: minEle,
      maxElevation: maxEle,
      duration: dur,
    );
  }

  /// Haversine distance between two WGS84 points in meters.
  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
