import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_source.dart';

/// Persists the user's selected map source across app restarts.
class MapSourcePreference {
  static const _key = 'selected_map_source_id';

  /// Load the previously selected map source. Returns [MapSource.openFreeMap]
  /// if none was saved.
  static Future<MapSource> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    if (id == null) return MapSource.openFreeMap;
    return MapSource.byId(id);
  }

  /// Save the selected map source id.
  static Future<void> save(MapSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, source.id);
  }
}
