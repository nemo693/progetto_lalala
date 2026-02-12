import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/map_source.dart';

/// Service for managing user-defined custom WMS sources.
///
/// Custom WMS sources are stored in a JSON file in the app's documents directory
/// and merged with the built-in sources for display in the map source picker.
class CustomWmsService {
  File? _customSourcesFile;
  List<MapSource> _customSources = [];
  bool _initialized = false;

  /// Initialize the service and load existing custom sources.
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _customSourcesFile = File('${appDir.path}/custom_wms_sources.json');
    await _load();
    _initialized = true;
  }

  /// Get all custom WMS sources.
  List<MapSource> get customSources => List.unmodifiable(_customSources);

  /// Add a new custom WMS source.
  Future<void> addSource(MapSource source) async {
    if (!_initialized) await initialize();
    if (source.type != MapSourceType.wms) {
      throw ArgumentError('Only WMS sources can be added as custom sources');
    }

    // Ensure unique ID
    if (_customSources.any((s) => s.id == source.id)) {
      throw ArgumentError('A source with ID "${source.id}" already exists');
    }

    _customSources.add(source);
    await _save();
  }

  /// Update an existing custom WMS source.
  Future<void> updateSource(String id, MapSource updatedSource) async {
    if (!_initialized) await initialize();

    final index = _customSources.indexWhere((s) => s.id == id);
    if (index == -1) {
      throw ArgumentError('Custom source with ID "$id" not found');
    }

    _customSources[index] = updatedSource;
    await _save();
  }

  /// Delete a custom WMS source by ID.
  Future<void> deleteSource(String id) async {
    if (!_initialized) await initialize();

    _customSources.removeWhere((s) => s.id == id);
    await _save();
  }

  /// Load custom sources from disk.
  Future<void> _load() async {
    if (_customSourcesFile == null || !await _customSourcesFile!.exists()) {
      _customSources = [];
      return;
    }

    try {
      final content = await _customSourcesFile!.readAsString();
      final json = jsonDecode(content) as List;
      _customSources = json
          .map((item) => _mapSourceFromJson(item as Map<String, dynamic>))
          .toList();
      debugPrint('[CustomWmsService] Loaded ${_customSources.length} custom WMS sources');
    } catch (e) {
      debugPrint('[CustomWmsService] Failed to load custom sources: $e');
      _customSources = [];
    }
  }

  /// Save custom sources to disk.
  Future<void> _save() async {
    if (_customSourcesFile == null) return;

    try {
      final json = _customSources.map((s) => _mapSourceToJson(s)).toList();
      await _customSourcesFile!.writeAsString(jsonEncode(json), flush: true);
      debugPrint('[CustomWmsService] Saved ${_customSources.length} custom WMS sources');
    } catch (e) {
      debugPrint('[CustomWmsService] Failed to save custom sources: $e');
    }
  }

  /// Convert MapSource to JSON.
  Map<String, dynamic> _mapSourceToJson(MapSource source) => {
        'id': source.id,
        'name': source.name,
        'wmsBaseUrl': source.wmsBaseUrl,
        'wmsLayers': source.wmsLayers,
        'wmsCrs': source.wmsCrs,
        'wmsFormat': source.wmsFormat,
        'attribution': source.attribution,
        'tileSize': source.tileSize,
        'avgTileSizeBytes': source.avgTileSizeBytes,
      };

  /// Convert JSON to MapSource.
  MapSource _mapSourceFromJson(Map<String, dynamic> json) => MapSource(
        id: json['id'] as String,
        name: json['name'] as String,
        type: MapSourceType.wms,
        url: '', // WMS sources don't use the url field
        wmsBaseUrl: json['wmsBaseUrl'] as String,
        wmsLayers: json['wmsLayers'] as String,
        wmsCrs: json['wmsCrs'] as String? ?? 'EPSG:3857',
        wmsFormat: json['wmsFormat'] as String? ?? 'image/jpeg',
        attribution: json['attribution'] as String? ?? '',
        tileSize: json['tileSize'] as int? ?? 256,
        avgTileSizeBytes: json['avgTileSizeBytes'] as int? ?? 60000,
      );
}
