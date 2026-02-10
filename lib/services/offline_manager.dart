import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../models/map_source.dart';
import '../utils/tile_calculator.dart';

/// Progress update during tile download.
class DownloadProgress {
  final double progressPercent;
  final bool isComplete;
  final String? error;

  const DownloadProgress({
    required this.progressPercent,
    this.isComplete = false,
    this.error,
  });

  @override
  String toString() =>
      'DownloadProgress(${(progressPercent * 100).toStringAsFixed(1)}%)';
}

/// Metadata for a downloaded offline region.
class OfflineRegion {
  final int id;
  final String name;
  final BoundingBox bounds;
  final int minZoom;
  final int maxZoom;

  const OfflineRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
  });
}

/// Manages offline map regions using MapLibre's native offline API.
///
/// Uses the built-in [downloadOfflineRegion], [getListOfRegions], and
/// [deleteOfflineRegion] functions from maplibre_gl. Tiles are stored in
/// MapLibre's native cache and served automatically when offline.
class OfflineManager {
  bool _initialized = false;

  /// Initialize the offline manager.
  Future<void> initialize() async {
    // Set a generous tile count limit (default is 6000 which is too low
    // for outdoor use at higher zoom levels).
    await ml.setOfflineTileCountLimit(50000);
    _initialized = true;
  }

  /// Download tiles for a bounding box at the given zoom range.
  ///
  /// Returns a stream of [DownloadProgress] updates.
  /// The [mapStyleUrl] specifies which style (and its tile sources) to cache.
  Stream<DownloadProgress> downloadRegion({
    required String regionName,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
    required String mapStyleUrl,
  }) {
    final controller = StreamController<DownloadProgress>();

    if (!_initialized) {
      controller.add(const DownloadProgress(
        progressPercent: 0,
        isComplete: true,
        error: 'OfflineManager not initialized',
      ));
      controller.close();
      return controller.stream;
    }

    final definition = ml.OfflineRegionDefinition(
      bounds: ml.LatLngBounds(
        southwest: ml.LatLng(bounds.minLat, bounds.minLon),
        northeast: ml.LatLng(bounds.maxLat, bounds.maxLon),
      ),
      mapStyleUrl: mapStyleUrl,
      minZoom: minZoom.toDouble(),
      maxZoom: maxZoom.toDouble(),
    );

    _doDownload(definition, regionName, controller);

    return controller.stream;
  }

  /// Runs the actual download and pushes progress to [controller].
  Future<void> _doDownload(
    ml.OfflineRegionDefinition definition,
    String regionName,
    StreamController<DownloadProgress> controller,
  ) async {
    debugPrint('[OfflineManager] Starting download: $regionName, '
        'style=${definition.mapStyleUrl}, '
        'zoom=${definition.minZoom}-${definition.maxZoom}');
    try {
      await ml.downloadOfflineRegion(
        definition,
        metadata: {'name': regionName},
        onEvent: (event) {
          if (controller.isClosed) return;
          if (event is ml.Success) {
            debugPrint('[OfflineManager] Download complete: $regionName');
            controller.add(const DownloadProgress(
              progressPercent: 1.0,
              isComplete: true,
            ));
            controller.close();
          } else if (event is ml.Error) {
            final errorMsg = event.cause.message ?? 'Unknown error';
            debugPrint('[OfflineManager] Download error: $regionName — $errorMsg');
            controller.add(DownloadProgress(
              progressPercent: 0,
              isComplete: true,
              error: errorMsg,
            ));
            controller.close();
          } else if (event is ml.InProgress) {
            final progress = event.progress;
            controller.add(DownloadProgress(
              progressPercent: progress / 100.0,
            ));
          } else {
            debugPrint('[OfflineManager] Unknown event: ${event.runtimeType}');
          }
        },
      );
    } catch (e, stack) {
      debugPrint('[OfflineManager] Download exception: $regionName — $e\n$stack');
      if (!controller.isClosed) {
        controller.add(DownloadProgress(
          progressPercent: 0,
          isComplete: true,
          error: 'Download failed: $e',
        ));
        controller.close();
      }
    }
  }

  /// Download tiles for a route with a buffer distance.
  ///
  /// [coordinatePairs] should be a list of [lat, lon] pairs from the route.
  /// [bufferMeters] is the distance to buffer around the route (default 5km).
  Stream<DownloadProgress> downloadRouteRegion({
    required String regionName,
    required List<List<double>> coordinatePairs,
    required int minZoom,
    required int maxZoom,
    required String mapStyleUrl,
    double bufferMeters = 5000,
  }) {
    final bbox = computeRouteBBox(coordinatePairs);
    if (bbox == null) {
      final controller = StreamController<DownloadProgress>();
      controller.add(const DownloadProgress(
        progressPercent: 0,
        isComplete: true,
        error: 'Empty route',
      ));
      controller.close();
      return controller.stream;
    }

    final bufferedBBox = computeBufferedBBox(bbox, bufferMeters);

    return downloadRegion(
      regionName: regionName,
      bounds: bufferedBBox,
      minZoom: minZoom,
      maxZoom: maxZoom,
      mapStyleUrl: mapStyleUrl,
    );
  }

  /// List all saved offline regions.
  Future<List<OfflineRegion>> listRegions() async {
    if (!_initialized) return [];

    final nativeRegions = await ml.getListOfRegions();

    return nativeRegions.map((r) {
      final name = r.metadata['name'] as String? ??
          'Region ${r.id}';
      return OfflineRegion(
        id: r.id,
        name: name,
        bounds: BoundingBox(
          minLat: r.definition.bounds.southwest.latitude,
          minLon: r.definition.bounds.southwest.longitude,
          maxLat: r.definition.bounds.northeast.latitude,
          maxLon: r.definition.bounds.northeast.longitude,
        ),
        minZoom: r.definition.minZoom.round(),
        maxZoom: r.definition.maxZoom.round(),
      );
    }).toList();
  }

  /// Rename an offline region by updating its metadata.
  Future<void> renameRegion(int regionId, String newName) async {
    if (!_initialized) return;
    await ml.updateOfflineRegionMetadata(regionId, {'name': newName});
  }

  /// Delete an offline region by its native ID.
  Future<void> deleteRegion(int regionId) async {
    if (!_initialized) return;
    await ml.deleteOfflineRegion(regionId);
  }

  /// Delete all offline regions.
  Future<void> clearAll() async {
    if (!_initialized) return;
    final regions = await ml.getListOfRegions();
    for (final r in regions) {
      await ml.deleteOfflineRegion(r.id);
    }
  }

  /// Set MapLibre to offline mode (no network requests).
  Future<void> setOffline(bool offline) async {
    await ml.setOffline(offline);
  }

  /// Estimate tile count for a bounding box at given zoom range.
  /// Useful for showing the user what they're about to download.
  int estimateTileCount(BoundingBox bounds, int minZoom, int maxZoom) {
    final tiles = enumerateTileCoords(
      bbox: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    return tiles.length;
  }

  /// Estimate download size in bytes using source-specific tile size.
  int estimateSize(int tileCount, {int bytesPerTile = 25000}) {
    return tileCount * bytesPerTile;
  }

  /// Download tiles for multiple map sources in the same region.
  ///
  /// Each source is downloaded sequentially. Progress is reported as an
  /// overall percentage across all sources.
  Stream<DownloadProgress> downloadRegionMultiSource({
    required String regionName,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
    required List<MapSource> sources,
  }) {
    final controller = StreamController<DownloadProgress>();

    _downloadMultipleSources(
      regionName: regionName,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      sources: sources,
      controller: controller,
    );

    return controller.stream;
  }

  Future<void> _downloadMultipleSources({
    required String regionName,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
    required List<MapSource> sources,
    required StreamController<DownloadProgress> controller,
  }) async {
    final total = sources.length;

    for (int i = 0; i < total; i++) {
      if (controller.isClosed) return;

      final source = sources[i];
      final suffix = total > 1 ? ' (${source.name})' : '';
      final name = '$regionName$suffix';

      // Resolve the style URL (raster sources use a local HTTP server)
      String styleUrl;
      try {
        styleUrl = await source.offlineStyleUrl;
        debugPrint('[OfflineManager] Resolved style URL for ${source.name}: $styleUrl');
      } catch (e) {
        debugPrint('[OfflineManager] Failed to resolve style URL for ${source.name}: $e');
        if (!controller.isClosed) {
          controller.add(DownloadProgress(
            progressPercent: (i + 1) / total,
            error: '${source.name}: Failed to prepare style — $e',
          ));
        }
        continue;
      }

      final stream = downloadRegion(
        regionName: name,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        mapStyleUrl: styleUrl,
      );

      await for (final progress in stream) {
        if (controller.isClosed) return;

        // Scale progress: each source is 1/total of overall progress
        final baseProgress = i / total;
        final sourceContribution = progress.progressPercent / total;
        final overallProgress = baseProgress + sourceContribution;

        if (progress.isComplete && progress.error != null) {
          // Source failed — report error but continue with next source
          controller.add(DownloadProgress(
            progressPercent: overallProgress,
            error: '${source.name}: ${progress.error}',
          ));
        } else if (progress.isComplete && i == total - 1) {
          // Last source completed
          controller.add(const DownloadProgress(
            progressPercent: 1.0,
            isComplete: true,
          ));
          controller.close();
        } else if (progress.isComplete) {
          // Non-last source completed, emit progress but don't close
          controller.add(DownloadProgress(
            progressPercent: (i + 1) / total,
          ));
        } else {
          controller.add(DownloadProgress(
            progressPercent: overallProgress,
          ));
        }
      }
    }

    // Stop the local style server (used for raster source downloads)
    await LocalStyleServer.stopAll();

    if (!controller.isClosed) {
      controller.add(const DownloadProgress(
        progressPercent: 1.0,
        isComplete: true,
      ));
      controller.close();
    }
  }

  /// Clean up.
  void dispose() {
    _initialized = false;
    LocalStyleServer.stopAll();
  }
}
