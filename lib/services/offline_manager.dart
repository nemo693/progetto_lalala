import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:path_provider/path_provider.dart';

import '../models/map_source.dart';
import '../utils/tile_calculator.dart';
import 'wms_tile_server.dart';

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
  final String styleUrl;

  /// True if this is a WMS region (not tracked by MapLibre native API)
  final bool isWms;

  const OfflineRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.styleUrl,
    this.isWms = false,
  });

  /// Check if this region was downloaded for a given [MapSource].
  ///
  /// Vector sources match by direct URL comparison.
  /// Raster sources match by checking if the style URL contains the source id
  /// (local style server URLs have the format `/style/{id}.json`).
  /// WMS sources match by checking if the styleUrl is `wms://{sourceId}`.
  bool matchesSource(MapSource source) {
    if (source.type == MapSourceType.vector) {
      return styleUrl == source.url;
    }
    if (source.type == MapSourceType.wms) {
      // WMS regions have styleUrl = "wms://{sourceId}"
      return styleUrl == 'wms://${source.id}';
    }
    // Raster XYZ: local style server URL contains the source id
    return styleUrl.contains('/style/${source.id}.');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bounds': {
      'minLat': bounds.minLat,
      'minLon': bounds.minLon,
      'maxLat': bounds.maxLat,
      'maxLon': bounds.maxLon,
    },
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'styleUrl': styleUrl,
    'isWms': isWms,
  };

  factory OfflineRegion.fromJson(Map<String, dynamic> json) => OfflineRegion(
    id: json['id'] as int,
    name: json['name'] as String,
    bounds: BoundingBox(
      minLat: json['bounds']['minLat'] as double,
      minLon: json['bounds']['minLon'] as double,
      maxLat: json['bounds']['maxLat'] as double,
      maxLon: json['bounds']['maxLon'] as double,
    ),
    minZoom: json['minZoom'] as int,
    maxZoom: json['maxZoom'] as int,
    styleUrl: json['styleUrl'] as String,
    isWms: json['isWms'] as bool? ?? false,
  );
}

/// Manages offline map regions using MapLibre's native offline API.
///
/// Uses the built-in [downloadOfflineRegion], [getListOfRegions], and
/// [deleteOfflineRegion] functions from maplibre_gl. Tiles are stored in
/// MapLibre's native cache and served automatically when offline.
///
/// WMS tiles are tracked separately (MapLibre doesn't know about them)
/// and stored in a JSON metadata file.
class OfflineManager {
  bool _initialized = false;
  File? _wmsMetadataFile;
  int _nextWmsId = 1000; // WMS region IDs start at 1000 to avoid MapLibre ID conflicts

  /// Initialize the offline manager.
  Future<void> initialize() async {
    // Set a generous tile count limit (default is 6000 which is too low
    // for outdoor use at higher zoom levels).
    await ml.setOfflineTileCountLimit(50000);

    // Initialize WMS metadata file
    final appDir = await getApplicationDocumentsDirectory();
    _wmsMetadataFile = File('${appDir.path}/wms_regions.json');

    _initialized = true;
  }

  /// Load WMS region metadata from disk.
  Future<List<OfflineRegion>> _loadWmsRegions() async {
    if (_wmsMetadataFile == null || !await _wmsMetadataFile!.exists()) {
      return [];
    }
    try {
      final content = await _wmsMetadataFile!.readAsString();
      final json = jsonDecode(content) as List;
      return json.map((item) => OfflineRegion.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[OfflineManager] Failed to load WMS metadata: $e');
      return [];
    }
  }

  /// Save WMS region metadata to disk.
  Future<void> _saveWmsRegions(List<OfflineRegion> regions) async {
    if (_wmsMetadataFile == null) return;
    try {
      final json = regions.map((r) => r.toJson()).toList();
      await _wmsMetadataFile!.writeAsString(jsonEncode(json), flush: true);
    } catch (e) {
      debugPrint('[OfflineManager] Failed to save WMS metadata: $e');
    }
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

  /// List all saved offline regions (both MapLibre and WMS).
  Future<List<OfflineRegion>> listRegions() async {
    if (!_initialized) return [];

    // Get MapLibre native regions
    final nativeRegions = await ml.getListOfRegions();
    final mapLibreList = nativeRegions.map((r) {
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
        styleUrl: r.definition.mapStyleUrl,
        isWms: false,
      );
    }).toList();

    // Get WMS regions
    final wmsList = await _loadWmsRegions();

    // Combine and return
    return [...mapLibreList, ...wmsList];
  }

  /// Rename an offline region by updating its metadata.
  Future<void> renameRegion(int regionId, String newName) async {
    if (!_initialized) return;

    // Check if it's a WMS region
    if (regionId >= _nextWmsId) {
      final wmsRegions = await _loadWmsRegions();
      final index = wmsRegions.indexWhere((r) => r.id == regionId);
      if (index >= 0) {
        final updated = OfflineRegion(
          id: wmsRegions[index].id,
          name: newName,
          bounds: wmsRegions[index].bounds,
          minZoom: wmsRegions[index].minZoom,
          maxZoom: wmsRegions[index].maxZoom,
          styleUrl: wmsRegions[index].styleUrl,
          isWms: true,
        );
        wmsRegions[index] = updated;
        await _saveWmsRegions(wmsRegions);
      }
    } else {
      // MapLibre region
      await ml.updateOfflineRegionMetadata(regionId, {'name': newName});
    }
  }

  /// Delete an offline region by its ID.
  Future<void> deleteRegion(int regionId) async {
    if (!_initialized) return;

    // Check if it's a WMS region
    if (regionId >= _nextWmsId) {
      final wmsRegions = await _loadWmsRegions();
      final region = wmsRegions.firstWhere((r) => r.id == regionId);

      // Delete the cached tiles
      // Extract source ID from styleUrl (format: "wms://{sourceId}")
      final sourceId = region.styleUrl.replaceFirst('wms://', '');
      await WmsTileServer.clearCache(sourceId);

      // Remove from metadata
      wmsRegions.removeWhere((r) => r.id == regionId);
      await _saveWmsRegions(wmsRegions);
    } else {
      // MapLibre region
      await ml.deleteOfflineRegion(regionId);
    }
  }

  /// Delete all offline regions (both MapLibre and WMS).
  Future<void> clearAll() async {
    if (!_initialized) return;

    // Clear MapLibre regions
    final regions = await ml.getListOfRegions();
    for (final r in regions) {
      await ml.deleteOfflineRegion(r.id);
    }

    // Clear WMS regions
    final wmsRegions = await _loadWmsRegions();
    for (final region in wmsRegions) {
      final sourceId = region.styleUrl.replaceFirst('wms://', '');
      await WmsTileServer.clearCache(sourceId);
    }
    await _saveWmsRegions([]);
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

  // ── WMS tile download ─────────────────────────────────────────────

  /// Download WMS tiles for a bounding box, caching them to disk.
  ///
  /// Unlike base map downloads (which use MapLibre's native offline API),
  /// WMS tiles are fetched individually via HTTP and stored in [WmsTileServer]'s
  /// disk cache. They are served to MapLibre through the local tile proxy.
  Stream<DownloadProgress> downloadWmsRegion({
    required MapSource wmsSource,
    required String regionName,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    final controller = StreamController<DownloadProgress>();
    _doWmsDownload(
      wmsSource: wmsSource,
      regionName: regionName,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      controller: controller,
    );
    return controller.stream;
  }

  Future<void> _doWmsDownload({
    required MapSource wmsSource,
    required String regionName,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
    required StreamController<DownloadProgress> controller,
  }) async {
    final tiles = enumerateTileCoords(
      bbox: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    debugPrint('[OfflineManager] WMS download: $regionName, '
        '${tiles.length} tiles, zoom $minZoom-$maxZoom');

    if (tiles.isEmpty) {
      controller.add(const DownloadProgress(
        progressPercent: 1.0,
        isComplete: true,
      ));
      controller.close();
      return;
    }

    int completed = 0;
    int errors = 0;
    int cached = 0;

    // Limit concurrent requests to avoid overwhelming the WMS server
    const maxConcurrent = 4;

    // Use a list-based queue instead of StreamController to avoid deadlock
    final queue = <Future<void>>[];

    for (final tile in tiles) {
      if (controller.isClosed) break;

      // Wait until we have room in the queue
      while (queue.length >= maxConcurrent) {
        if (controller.isClosed) break;
        await queue.removeAt(0);
      }

      if (controller.isClosed) break;

      final future = () async {
        try {
          // Skip if already cached
          final isCached = await WmsTileServer.isTileCached(
            wmsSource.id, tile.z, tile.x, tile.y,
          );
          if (isCached) {
            cached++;
          } else {
            final bytes = await WmsTileServer.fetchWmsTile(
              wmsSource, tile.z, tile.x, tile.y,
            );
            if (bytes != null) {
              await WmsTileServer.cacheTile(
                wmsSource.id, tile.z, tile.x, tile.y, bytes,
              );
            } else {
              errors++;
            }
          }
        } catch (e) {
          debugPrint('[OfflineManager] WMS tile error ${tile.z}/${tile.x}/${tile.y}: $e');
          errors++;
        }

        completed++;
        if (!controller.isClosed) {
          // Emit progress every 10 tiles or on completion
          if (completed % 10 == 0 || completed >= tiles.length) {
            controller.add(DownloadProgress(
              progressPercent: completed / tiles.length,
              isComplete: completed >= tiles.length,
              error: (completed >= tiles.length && errors > 0)
                  ? '$errors tiles failed ($cached already cached)'
                  : null,
            ));
          }
          if (completed >= tiles.length) {
            debugPrint('[OfflineManager] WMS download complete: $regionName '
                '(${tiles.length} tiles, $cached cached, $errors errors)');

            // Save metadata for this WMS region
            await _saveWmsRegionMetadata(
              regionName: regionName,
              sourceId: wmsSource.id,
              bounds: bounds,
              minZoom: minZoom,
              maxZoom: maxZoom,
            );

            controller.close();
          }
        }
      }();

      queue.add(future);
    }

    // Wait for all remaining downloads to complete
    await Future.wait(queue);

    if (!controller.isClosed) {
      controller.add(const DownloadProgress(
        progressPercent: 1.0,
        isComplete: true,
      ));

      // Save metadata for this WMS region
      await _saveWmsRegionMetadata(
        regionName: regionName,
        sourceId: wmsSource.id,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

      controller.close();
    }
  }

  /// Save metadata for a completed WMS download.
  Future<void> _saveWmsRegionMetadata({
    required String regionName,
    required String sourceId,
    required BoundingBox bounds,
    required int minZoom,
    required int maxZoom,
  }) async {
    final wmsRegions = await _loadWmsRegions();

    // Check if a region with this name already exists
    final existingIndex = wmsRegions.indexWhere((r) => r.name == regionName);

    final region = OfflineRegion(
      id: existingIndex >= 0 ? wmsRegions[existingIndex].id : _nextWmsId++,
      name: regionName,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      styleUrl: 'wms://$sourceId', // Store source ID for deletion
      isWms: true,
    );

    if (existingIndex >= 0) {
      wmsRegions[existingIndex] = region;
    } else {
      wmsRegions.add(region);
    }

    await _saveWmsRegions(wmsRegions);
    debugPrint('[OfflineManager] Saved WMS region metadata: $regionName (id=${region.id})');
  }

  /// Clean up.
  void dispose() {
    _initialized = false;
    LocalStyleServer.stopAll();
  }
}
