import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_source.dart';
import 'custom_wms_service.dart';

/// Persists the user's selected map source and hidden WMS IDs across app restarts.
class MapSourcePreference {
  static const _key = 'selected_map_source_id';
  static const _hiddenWmsKey = 'hidden_wms_source_ids';

  /// Load the previously selected map source. Returns [MapSource.openFreeMap]
  /// if none was saved.
  static Future<MapSource> load(CustomWmsService customWmsService) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    if (id == null) return MapSource.openFreeMap;
    return MapSource.byId(id, customSources: customWmsService.customSources);
  }

  /// Save the selected map source id.
  static Future<void> save(MapSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, source.id);
  }

  /// Load the set of built-in WMS source IDs the user has hidden.
  static Future<Set<String>> loadHiddenWmsIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_hiddenWmsKey);
    return ids?.toSet() ?? {};
  }

  /// Save the set of hidden built-in WMS source IDs.
  static Future<void> saveHiddenWmsIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenWmsKey, ids.toList());
  }
}
