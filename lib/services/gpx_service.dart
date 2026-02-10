import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gpx/gpx.dart';
import '../models/route.dart';
import '../models/waypoint.dart' as model;

/// Result of importing a GPX file: a route and its waypoints.
class GpxImportResult {
  final NavRoute route;
  final List<model.Waypoint> waypoints;

  const GpxImportResult({required this.route, required this.waypoints});
}

/// Handles GPX import, export, and live track recording.
class GpxService {
  // ── Import ──────────────────────────────────────────────────────────────

  /// Parse a GPX file from disk into a route + waypoints.
  Future<GpxImportResult> importFromFile(String filePath) async {
    final file = File(filePath);
    final xmlString = await file.readAsString();
    final fileName = file.uri.pathSegments.last.replaceAll('.gpx', '');
    return importFromString(xmlString, fallbackName: fileName, filePath: filePath);
  }

  /// Parse a GPX XML string into a route + waypoints.
  /// Uses [compute] isolate for large files.
  Future<GpxImportResult> importFromString(
    String xmlString, {
    String fallbackName = 'Imported route',
    String? filePath,
  }) async {
    // Parse in an isolate to avoid UI jank on large files
    final parsed = await compute(_parseGpx, xmlString);
    return _buildResult(parsed, fallbackName: fallbackName, filePath: filePath);
  }

  /// Top-level function for isolate parsing (must be static/top-level).
  static Gpx _parseGpx(String xml) => GpxReader().fromString(xml);

  GpxImportResult _buildResult(
    Gpx gpx, {
    required String fallbackName,
    String? filePath,
  }) {
    // Extract track points from all tracks and segments
    final trackPoints = <TrackPoint>[];
    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat != null && pt.lon != null) {
            trackPoints.add(TrackPoint(
              latitude: pt.lat!,
              longitude: pt.lon!,
              elevation: pt.ele,
              timestamp: pt.time,
            ));
          }
        }
      }
    }

    // Also pull points from <rte> elements (less common but valid)
    for (final rte in gpx.rtes) {
      for (final pt in rte.rtepts) {
        if (pt.lat != null && pt.lon != null) {
          trackPoints.add(TrackPoint(
            latitude: pt.lat!,
            longitude: pt.lon!,
            elevation: pt.ele,
            timestamp: pt.time,
          ));
        }
      }
    }

    // Determine route name
    String name = fallbackName;
    if (gpx.trks.isNotEmpty && gpx.trks.first.name != null) {
      name = gpx.trks.first.name!;
    } else if (gpx.rtes.isNotEmpty && gpx.rtes.first.name != null) {
      name = gpx.rtes.first.name!;
    } else if (gpx.metadata?.name != null) {
      name = gpx.metadata!.name!;
    }

    // Determine description
    String? desc;
    if (gpx.trks.isNotEmpty && gpx.trks.first.desc != null) {
      desc = gpx.trks.first.desc;
    } else if (gpx.metadata?.desc != null) {
      desc = gpx.metadata!.desc;
    }

    final routeId = DateTime.now().millisecondsSinceEpoch.toString();
    final route = NavRoute.fromPoints(
      id: routeId,
      name: name,
      description: desc,
      points: trackPoints,
      source: RouteSource.imported,
      filePath: filePath,
    );

    // Extract waypoints
    final waypoints = <model.Waypoint>[];
    for (int i = 0; i < gpx.wpts.length; i++) {
      final wpt = gpx.wpts[i];
      if (wpt.lat == null || wpt.lon == null) continue;
      waypoints.add(model.Waypoint(
        id: '${routeId}_wpt_$i',
        name: wpt.name ?? 'Waypoint ${i + 1}',
        description: wpt.desc,
        latitude: wpt.lat!,
        longitude: wpt.lon!,
        elevation: wpt.ele,
        symbol: _mapGpxSymbol(wpt.sym),
        routeId: routeId,
        createdAt: wpt.time ?? DateTime.now(),
      ));
    }

    return GpxImportResult(route: route, waypoints: waypoints);
  }

  /// Map GPX symbol strings to our internal symbol set.
  static String _mapGpxSymbol(String? gpxSym) {
    if (gpxSym == null) return 'generic';
    final lower = gpxSym.toLowerCase();
    if (lower.contains('summit') || lower.contains('peak')) return 'summit';
    if (lower.contains('hut') || lower.contains('shelter')) return 'hut';
    if (lower.contains('parking')) return 'parking';
    if (lower.contains('water') || lower.contains('spring')) return 'water';
    return 'generic';
  }

  // ── Export ──────────────────────────────────────────────────────────────

  /// Generate a GPX XML string from a route and optional waypoints.
  String exportToString(NavRoute route, [List<model.Waypoint>? waypoints]) {
    final gpx = Gpx();
    gpx.creator = 'AlpineNav';
    gpx.metadata = Metadata(
      name: route.name,
      desc: route.description,
      time: route.createdAt,
    );

    // Build track
    final trk = Trk(
      name: route.name,
      desc: route.description,
    );

    final seg = Trkseg();
    for (final pt in route.points) {
      seg.trkpts.add(Wpt(
        lat: pt.latitude,
        lon: pt.longitude,
        ele: pt.elevation,
        time: pt.timestamp,
      ));
    }
    trk.trksegs.add(seg);
    gpx.trks.add(trk);

    // Add waypoints
    if (waypoints != null) {
      for (final wpt in waypoints) {
        gpx.wpts.add(Wpt(
          lat: wpt.latitude,
          lon: wpt.longitude,
          ele: wpt.elevation,
          name: wpt.name,
          desc: wpt.description,
          sym: wpt.symbol,
          time: wpt.createdAt,
        ));
      }
    }

    return GpxWriter().asString(gpx, pretty: true);
  }

  /// Write a GPX file to disk.
  Future<File> exportToFile(
    NavRoute route,
    String outputPath, [
    List<model.Waypoint>? waypoints,
  ]) async {
    final xml = exportToString(route, waypoints);
    final file = File(outputPath);
    return file.writeAsString(xml);
  }
}

// ── Recording ────────────────────────────────────────────────────────────────

/// State of the track recorder.
enum RecordingState { idle, recording, paused }

/// Live track recorder that accumulates GPS fixes and computes running stats.
class TrackRecorder {
  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  final List<TrackPoint> _points = [];
  List<TrackPoint> get points => List.unmodifiable(_points);

  DateTime? _startTime;
  DateTime? _pauseTime;
  Duration _pausedDuration = Duration.zero;

  // Running stats
  double _distance = 0;
  double _elevationGain = 0;
  double _elevationLoss = 0;
  double? _minElevation;
  double? _maxElevation;

  double get distance => _distance;
  double get elevationGain => _elevationGain;
  double get elevationLoss => _elevationLoss;
  double? get minElevation => _minElevation;
  double? get maxElevation => _maxElevation;

  /// Elapsed time excluding pauses.
  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    final end = _state == RecordingState.paused
        ? _pauseTime!
        : DateTime.now();
    return end.difference(_startTime!) - _pausedDuration;
  }

  /// Average pace in min/km (returns null if distance < 10m).
  double? get paceMinPerKm {
    if (_distance < 10) return null;
    final minutes = elapsed.inSeconds / 60.0;
    return minutes / (_distance / 1000.0);
  }

  int get pointCount => _points.length;

  /// Minimum GPS accuracy in meters to accept a fix (discard worse fixes).
  double accuracyThreshold;

  TrackRecorder({this.accuracyThreshold = 30.0});

  /// Start recording.
  void start() {
    if (_state != RecordingState.idle) return;
    _state = RecordingState.recording;
    _startTime = DateTime.now();
    _points.clear();
    _distance = 0;
    _elevationGain = 0;
    _elevationLoss = 0;
    _minElevation = null;
    _maxElevation = null;
    _pausedDuration = Duration.zero;
  }

  /// Pause recording (GPS fixes are ignored while paused).
  void pause() {
    if (_state != RecordingState.recording) return;
    _state = RecordingState.paused;
    _pauseTime = DateTime.now();
  }

  /// Resume recording after pause.
  void resume() {
    if (_state != RecordingState.paused) return;
    _pausedDuration += DateTime.now().difference(_pauseTime!);
    _state = RecordingState.recording;
  }

  /// Stop recording and return the final list of points.
  List<TrackPoint> stop() {
    _state = RecordingState.idle;
    return List.unmodifiable(_points);
  }

  /// Add a GPS fix from the location service.
  /// Returns true if the fix was accepted, false if filtered out.
  bool addPosition(Position pos) {
    if (_state != RecordingState.recording) return false;

    // Filter poor accuracy
    if (pos.accuracy > accuracyThreshold) return false;

    final point = TrackPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      elevation: pos.altitude != 0.0 ? pos.altitude : null,
      timestamp: pos.timestamp,
    );

    // Update min/max elevation
    if (point.elevation != null) {
      _minElevation = _minElevation == null
          ? point.elevation!
          : math.min(_minElevation!, point.elevation!);
      _maxElevation = _maxElevation == null
          ? point.elevation!
          : math.max(_maxElevation!, point.elevation!);
    }

    // Update running stats
    if (_points.isNotEmpty) {
      final prev = _points.last;
      _distance += RouteStats.compute([prev, point]).distance;

      final prevEle = prev.elevation;
      final currEle = point.elevation;
      if (prevEle != null && currEle != null) {
        final diff = currEle - prevEle;
        if (diff > 0) {
          _elevationGain += diff;
        } else {
          _elevationLoss += diff.abs();
        }
      }
    }

    _points.add(point);
    return true;
  }

  /// Build a NavRoute from the recorded points.
  NavRoute toRoute({required String name, String? description}) {
    return NavRoute(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      points: List.of(_points),
      distance: _distance,
      elevationGain: _elevationGain,
      elevationLoss: _elevationLoss,
      minElevation: _minElevation,
      maxElevation: _maxElevation,
      duration: elapsed,
      source: RouteSource.recorded,
      createdAt: DateTime.now(),
    );
  }
}
