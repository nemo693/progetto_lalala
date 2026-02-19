import 'package:flutter/material.dart';

import '../models/map_source.dart';
import '../services/custom_wms_service.dart';

/// Result returned by [WmsSourcesScreen] when popped.
class WmsSourcesResult {
  final Set<String> hiddenWmsIds;
  WmsSourcesResult({required this.hiddenWmsIds});
}

/// Screen for managing all WMS sources (built-in + custom).
///
/// Built-in WMS sources can be shown/hidden via a visibility toggle.
/// Custom WMS sources can be added, edited, and deleted.
class WmsSourcesScreen extends StatefulWidget {
  final CustomWmsService customWmsService;
  final Set<String> hiddenWmsIds;

  const WmsSourcesScreen({
    super.key,
    required this.customWmsService,
    required this.hiddenWmsIds,
  });

  @override
  State<WmsSourcesScreen> createState() => _WmsSourcesScreenState();
}

class _WmsSourcesScreenState extends State<WmsSourcesScreen> {
  late Set<String> _hiddenWmsIds;
  List<MapSource> _customSources = [];

  /// Built-in WMS sources (from MapSource.all).
  List<MapSource> get _builtinWmsSources =>
      MapSource.all.where((s) => s.type == MapSourceType.wms).toList();

  @override
  void initState() {
    super.initState();
    _hiddenWmsIds = Set.from(widget.hiddenWmsIds);
    _loadSources();
  }

  void _loadSources() {
    setState(() {
      _customSources = widget.customWmsService.customSources;
    });
  }

  void _toggleBuiltinVisibility(String id) {
    setState(() {
      if (_hiddenWmsIds.contains(id)) {
        _hiddenWmsIds.remove(id);
      } else {
        _hiddenWmsIds.add(id);
      }
    });
  }

  Future<void> _addSource() async {
    final source = await showDialog<MapSource>(
      context: context,
      builder: (ctx) => const _WmsSourceDialog(),
    );

    if (source != null) {
      try {
        await widget.customWmsService.addSource(source);
        _loadSources();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Custom WMS source added'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _editSource(MapSource source) async {
    final updated = await showDialog<MapSource>(
      context: context,
      builder: (ctx) => _WmsSourceDialog(existingSource: source),
    );

    if (updated != null) {
      try {
        await widget.customWmsService.updateSource(source.id, updated);
        _loadSources();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Custom WMS source updated'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteSource(MapSource source) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete custom WMS source?',
            style: TextStyle(color: Colors.white70)),
        content: Text(
          source.name,
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
      await widget.customWmsService.deleteSource(source.id);
      _loadSources();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Return the updated hidden IDs to the caller
          // We use addPostFrameCallback to ensure Navigator result is set
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('WMS Sources',
              style: TextStyle(color: Colors.white70)),
          iconTheme: const IconThemeData(color: Colors.white70),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(
              context,
              WmsSourcesResult(hiddenWmsIds: _hiddenWmsIds),
            ),
          ),
        ),
        body: ListView(
          children: [
            // ── Built-in WMS section ──
            _buildSectionHeader('BUILT-IN'),
            ..._builtinWmsSources.map((source) {
              final isHidden = _hiddenWmsIds.contains(source.id);
              return _BuiltinWmsListItem(
                source: source,
                isHidden: isHidden,
                onToggleVisibility: () => _toggleBuiltinVisibility(source.id),
              );
            }),

            const SizedBox(height: 8),

            // ── Custom WMS section ──
            _buildSectionHeader('CUSTOM'),
            if (_customSources.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'No custom WMS sources yet.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ..._customSources.map((source) => _CustomWmsListItem(
                  source: source,
                  onEdit: () => _editSource(source),
                  onDelete: () => _deleteSource(source),
                )),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _addSource,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add custom WMS'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2)),
    );
  }
}

// ── Built-in WMS list item (read-only, with visibility toggle) ──

class _BuiltinWmsListItem extends StatelessWidget {
  final MapSource source;
  final bool isHidden;
  final VoidCallback onToggleVisibility;

  const _BuiltinWmsListItem({
    required this.source,
    required this.isHidden,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Icon(Icons.photo_library,
              color: isHidden ? Colors.white24 : Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: TextStyle(
                    color: isHidden ? Colors.white38 : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  source.wmsLayers ?? '',
                  style: TextStyle(
                    color: isHidden ? Colors.white24 : Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isHidden ? Icons.visibility_off : Icons.visibility,
              color: isHidden ? Colors.white24 : Colors.white54,
              size: 20,
            ),
            onPressed: onToggleVisibility,
            tooltip: isHidden ? 'Show in map picker' : 'Hide from map picker',
          ),
        ],
      ),
    );
  }
}

// ── Custom WMS list item (editable, deletable) ──

class _CustomWmsListItem extends StatelessWidget {
  final MapSource source;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomWmsListItem({
    required this.source,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.photo, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  source.wmsLayers ?? '',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  source.wmsBaseUrl ?? '',
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: Colors.white38, size: 20),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.white38, size: 20),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

// ── Add/Edit WMS dialog (reused from old custom_wms_screen.dart) ──

class _WmsSourceDialog extends StatefulWidget {
  final MapSource? existingSource;

  const _WmsSourceDialog({this.existingSource});

  @override
  State<_WmsSourceDialog> createState() => _WmsSourceDialogState();
}

class _WmsSourceDialogState extends State<_WmsSourceDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _layersController;
  late final TextEditingController _attributionController;
  String _selectedCrs = 'EPSG:3857';
  String _selectedFormat = 'image/jpeg';
  int _tileSize = 512;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSource;
    _idController = TextEditingController(text: existing?.id ?? '');
    _nameController = TextEditingController(text: existing?.name ?? '');
    _urlController = TextEditingController(text: existing?.wmsBaseUrl ?? '');
    _layersController = TextEditingController(text: existing?.wmsLayers ?? '');
    _attributionController =
        TextEditingController(text: existing?.attribution ?? '');
    _selectedCrs = existing?.wmsCrs ?? 'EPSG:3857';
    _selectedFormat = existing?.wmsFormat ?? 'image/jpeg';
    _tileSize = existing?.tileSize ?? 512;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _layersController.dispose();
    _attributionController.dispose();
    super.dispose();
  }

  void _save() {
    if (_idController.text.trim().isEmpty) {
      _showError('ID is required');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _showError('Name is required');
      return;
    }
    if (_urlController.text.trim().isEmpty) {
      _showError('WMS URL is required');
      return;
    }
    if (_layersController.text.trim().isEmpty) {
      _showError('Layer name is required');
      return;
    }

    final id = _idController.text.trim().toLowerCase().replaceAll(' ', '_');
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) {
      _showError(
          'ID can only contain lowercase letters, numbers, hyphens, and underscores');
      return;
    }

    final source = MapSource(
      id: id,
      name: _nameController.text.trim(),
      type: MapSourceType.wms,
      url: '',
      wmsBaseUrl: _urlController.text.trim(),
      wmsLayers: _layersController.text.trim(),
      wmsCrs: _selectedCrs,
      wmsFormat: _selectedFormat,
      attribution: _attributionController.text.trim(),
      tileSize: _tileSize,
      avgTileSizeBytes: _selectedFormat == 'image/jpeg' ? 60000 : 40000,
    );

    Navigator.pop(context, source);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingSource != null;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Text(
        isEditing ? 'Edit WMS Source' : 'Add WMS Source',
        style: const TextStyle(color: Colors.white70),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(
              controller: _idController,
              label: 'ID',
              hint: 'e.g. my_custom_wms',
              enabled: !isEditing,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _nameController,
              label: 'Display Name',
              hint: 'e.g. My Region Orthophoto',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _urlController,
              label: 'WMS Base URL',
              hint: 'https://example.com/wms',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _layersController,
              label: 'Layer Name(s)',
              hint: 'e.g. orthophoto_2023',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _attributionController,
              label: 'Attribution',
              hint: '\u00a9 Data Provider',
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Coordinate System',
              value: _selectedCrs,
              options: const [
                'EPSG:3857',
                'EPSG:4326',
                'EPSG:32632',
                'EPSG:32633',
              ],
              onChanged: (val) => setState(() => _selectedCrs = val!),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Image Format',
              value: _selectedFormat,
              options: const ['image/jpeg', 'image/png'],
              onChanged: (val) => setState(() => _selectedFormat = val!),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tile Size',
              value: _tileSize.toString(),
              options: const ['256', '512'],
              onChanged: (val) => setState(() => _tileSize = int.parse(val!)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          style: TextStyle(
            color: enabled ? Colors.white70 : Colors.white38,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: enabled ? Colors.black26 : Colors.black12,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.blue),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> options,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF1A1A2E),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            items: options
                .map((opt) => DropdownMenuItem(
                      value: opt,
                      child: Text(opt),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
