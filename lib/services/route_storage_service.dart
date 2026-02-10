import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/route.dart';
import '../models/waypoint.dart';
import 'gpx_service.dart';

/// Manages saving, loading, listing, and deleting routes on disk.
///
/// Routes are stored as GPX files in the app's documents directory under
/// a `routes/` subdirectory. A companion `.json` metadata file stores
/// extra fields (id, source, createdAt) not present in GPX.
class RouteStorageService {
  static const _routesDir = 'routes';

  final GpxService _gpxService = GpxService();

  /// Get (or create) the routes storage directory.
  Future<Directory> _getRoutesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_routesDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Save a route (and its waypoints) to disk.
  /// Returns the path to the saved GPX file.
  Future<String> saveRoute(NavRoute route, [List<Waypoint>? waypoints]) async {
    final dir = await _getRoutesDir();
    final safeName = route.id;

    // Save GPX file
    final gpxPath = '${dir.path}/$safeName.gpx';
    await _gpxService.exportToFile(route, gpxPath, waypoints);

    // Save metadata JSON (fields not in GPX: id, source, createdAt)
    final metaPath = '${dir.path}/$safeName.json';
    final meta = {
      'id': route.id,
      'source': route.source == RouteSource.imported ? 'imported' : 'recorded',
      'createdAt': route.createdAt.toIso8601String(),
    };
    await File(metaPath).writeAsString(jsonEncode(meta));

    return gpxPath;
  }

  /// List all saved routes (sorted by creation time, newest first).
  Future<List<NavRoute>> listRoutes() async {
    final dir = await _getRoutesDir();
    if (!await dir.exists()) return [];

    final routes = <NavRoute>[];
    final gpxFiles = await dir
        .list()
        .where((f) => f.path.endsWith('.gpx'))
        .toList();

    for (final file in gpxFiles) {
      try {
        final result = await _gpxService.importFromFile(file.path);
        final route = result.route;

        // Try to load metadata for accurate id/source/createdAt
        final metaPath = file.path.replaceAll('.gpx', '.json');
        final metaFile = File(metaPath);
        if (await metaFile.exists()) {
          final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
          routes.add(NavRoute(
            id: meta['id'] as String? ?? route.id,
            name: route.name,
            description: route.description,
            points: route.points,
            distance: route.distance,
            elevationGain: route.elevationGain,
            elevationLoss: route.elevationLoss,
            minElevation: route.minElevation,
            maxElevation: route.maxElevation,
            duration: route.duration,
            source: meta['source'] == 'recorded'
                ? RouteSource.recorded
                : RouteSource.imported,
            createdAt: meta['createdAt'] != null
                ? DateTime.parse(meta['createdAt'] as String)
                : route.createdAt,
            filePath: file.path,
          ));
        } else {
          routes.add(NavRoute(
            id: route.id,
            name: route.name,
            description: route.description,
            points: route.points,
            distance: route.distance,
            elevationGain: route.elevationGain,
            elevationLoss: route.elevationLoss,
            minElevation: route.minElevation,
            maxElevation: route.maxElevation,
            duration: route.duration,
            source: route.source,
            createdAt: route.createdAt,
            filePath: file.path,
          ));
        }
      } catch (_) {
        // Skip corrupt files
      }
    }

    routes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return routes;
  }

  /// Load a single route and its waypoints by ID.
  Future<GpxImportResult?> loadRoute(String id) async {
    final dir = await _getRoutesDir();
    final gpxFile = File('${dir.path}/$id.gpx');
    if (!await gpxFile.exists()) return null;
    return _gpxService.importFromFile(gpxFile.path);
  }

  /// Delete a route from disk.
  Future<void> deleteRoute(String id) async {
    final dir = await _getRoutesDir();
    final gpxFile = File('${dir.path}/$id.gpx');
    final metaFile = File('${dir.path}/$id.json');
    if (await gpxFile.exists()) await gpxFile.delete();
    if (await metaFile.exists()) await metaFile.delete();
  }

  /// Get the GPX file path for a route (for sharing/exporting).
  Future<String?> getGpxFilePath(String id) async {
    final dir = await _getRoutesDir();
    final gpxFile = File('${dir.path}/$id.gpx');
    if (await gpxFile.exists()) return gpxFile.path;
    return null;
  }

  /// Import a GPX file from an external path, copy it to routes directory.
  Future<NavRoute> importExternalFile(String externalPath) async {
    final result = await _gpxService.importFromFile(externalPath);
    await saveRoute(result.route, result.waypoints);
    return result.route;
  }
}
