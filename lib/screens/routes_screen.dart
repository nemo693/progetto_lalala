import 'package:flutter/material.dart';
import '../models/route.dart';
import '../services/route_storage_service.dart';

/// Screen for managing saved routes: list, view stats, delete, export.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final _storage = RouteStorageService();
  List<NavRoute>? _routes;
  bool _loading = true;

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
      ),
      body: _loading
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
    final dur = _formatDuration(route.duration);
    final source = route.source == RouteSource.recorded ? 'REC' : 'GPX';

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
                    '$distKm km  +${gainM}m  $dur',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontFamily: 'monospace',
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
}
