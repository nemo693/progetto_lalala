import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/route.dart';
import '../services/gpx_service.dart';
import '../services/route_storage_service.dart';

/// Screen for managing saved routes: list, view stats, delete, export.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final _storage = RouteStorageService();
  final _gpxService = GpxService();
  List<NavRoute>? _routes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() => _loading = true);
    final routes = await _storage.listRoutes();
    if (mounted) {
      setState(() {
        _routes = routes;
        _loading = false;
      });
    }
  }

  Future<void> _deleteRoute(NavRoute route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete route?', style: TextStyle(color: Colors.white70)),
        content: Text(
          route.name,
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
      await _storage.deleteRoute(route.id);
      _loadRoutes();
    }
  }

  Future<void> _importGpx() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final path = file.path;

      if (path == null || path.isEmpty) {
        _showError('Could not access file. Try copying it to Downloads folder.');
        return;
      }

      final lowerPath = path.toLowerCase();
      if (!lowerPath.endsWith('.gpx') && !lowerPath.endsWith('.xml')) {
        _showError('Please select a .gpx or .xml file');
        return;
      }

      final imported = await _gpxService.importFromFile(path);

      if (imported.route.points.isEmpty) {
        _showError('GPX file contains no track points');
        return;
      }

      await _storage.saveRoute(imported.route, imported.waypoints);

      // Return the imported route to the map immediately
      if (mounted) {
        Navigator.pop(context, imported.route);
      }
    } catch (e) {
      String errorMsg = 'Failed to import GPX';
      if (e.toString().contains('Permission')) {
        errorMsg = 'Storage permission denied. Check app settings.';
      } else if (e.toString().contains('FileSystemException')) {
        errorMsg = 'Could not read file. Try moving it to Downloads.';
      } else if (e.toString().contains('FormatException') || e.toString().contains('XmlParserException')) {
        errorMsg = 'Invalid GPX file format';
      } else {
        errorMsg = 'Failed to import: ${e.toString().split('\n').first}';
      }
      _showError(errorMsg);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _error = null);
    });
  }

  void _viewOnMap(NavRoute route) {
    // Pop back to map screen with the selected route
    Navigator.pop(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Routes', style: TextStyle(color: Colors.white70)),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white70),
            tooltip: 'Import GPX file',
            onPressed: _importGpx,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.red.shade900.withAlpha(200),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routes == null || _routes!.isEmpty
              ? const Center(
                  child: Text(
                    'No saved routes.\nImport a GPX file or record a track.',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _routes!.length,
                  itemBuilder: (ctx, i) => _RouteListItem(
                    route: _routes![i],
                    onTap: () => _viewOnMap(_routes![i]),
                    onDelete: () => _deleteRoute(_routes![i]),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _RouteListItem extends StatelessWidget {
  final NavRoute route;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RouteListItem({
    required this.route,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final distKm = (route.distance / 1000).toStringAsFixed(1);
    final gainM = route.elevationGain.round();
    final lossM = route.elevationLoss.round();
    final dur = _formatDuration(route.duration);
    final source = route.source == RouteSource.recorded ? 'REC' : 'GPX';
    final date = _formatDate(route.createdAt);
    final eleRange = route.minElevation != null && route.maxElevation != null
        ? '${route.minElevation!.round()}–${route.maxElevation!.round()}m'
        : null;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: route.source == RouteSource.recorded
                              ? Colors.red.withAlpha(50)
                              : Colors.blue.withAlpha(50),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          source,
                          style: TextStyle(
                            color: route.source == RouteSource.recorded
                                ? Colors.red.shade300
                                : Colors.blue.shade300,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          route.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$distKm km  +${gainM}m  -${lossM}m  $dur'
                    '${eleRange != null ? '  $eleRange' : ''}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }
}
