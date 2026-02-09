import 'package:flutter/material.dart';

import '../main.dart' show offlineManager;
import '../services/offline_manager.dart';
import '../utils/tile_calculator.dart';

/// Screen for managing downloaded offline map regions.
///
/// Lists all saved regions with their zoom range and bounds.
/// Allows deleting individual regions or clearing all cached data.
class OfflineRegionsScreen extends StatefulWidget {
  const OfflineRegionsScreen({super.key});

  @override
  State<OfflineRegionsScreen> createState() => _OfflineRegionsScreenState();
}

class _OfflineRegionsScreenState extends State<OfflineRegionsScreen> {
  List<OfflineRegion>? _regions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    setState(() => _loading = true);
    try {
      final regions = await offlineManager.listRegions();
      if (mounted) {
        setState(() {
          _regions = regions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _regions = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteRegion(OfflineRegion region) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete offline region?',
            style: TextStyle(color: Colors.white70)),
        content: Text(
          region.name,
          style: const TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await offlineManager.deleteRegion(region.id);
      _loadRegions();
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear all offline data?',
            style: TextStyle(color: Colors.white70)),
        content: const Text(
          'This will delete all downloaded map regions.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await offlineManager.clearAll();
      _loadRegions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRegions = _regions != null && _regions!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title:
            const Text('Offline Maps', style: TextStyle(color: Colors.white70)),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          if (hasRegions)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white38),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !hasRegions
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No offline regions.\n\n'
                      'Tap the download button on the map screen '
                      'to save an area for offline use.',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    // ── Summary header ────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      color: Colors.black26,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_regions!.length} region${_regions!.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    // ── Regions list ──────────────────────────────
                    Expanded(
                      child: ListView.builder(
                        itemCount: _regions!.length,
                        itemBuilder: (ctx, i) => _RegionListItem(
                          region: _regions![i],
                          onDelete: () => _deleteRegion(_regions![i]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _RegionListItem extends StatelessWidget {
  final OfflineRegion region;
  final VoidCallback onDelete;

  const _RegionListItem({required this.region, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final zoomRange = 'z${region.minZoom}-${region.maxZoom}';
    // Estimate tile count for display
    final tileCount = enumerateTileCoords(
      bbox: region.bounds,
      minZoom: region.minZoom,
      maxZoom: region.maxZoom,
    ).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.map, color: Colors.white24, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  region.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$zoomRange  ~$tileCount tiles',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.white24, size: 20),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}
