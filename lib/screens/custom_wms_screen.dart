import 'package:flutter/material.dart';

import '../models/map_source.dart';
import '../services/custom_wms_service.dart';

/// Screen for managing custom WMS sources.
///
/// Allows users to add, edit, and delete custom WMS endpoints
/// for orthophotos, hillshades, or other WMS layers.
class CustomWmsScreen extends StatefulWidget {
  final CustomWmsService customWmsService;

  const CustomWmsScreen({
    super.key,
    required this.customWmsService,
  });

  @override
  State<CustomWmsScreen> createState() => _CustomWmsScreenState();
}

class _CustomWmsScreenState extends State<CustomWmsScreen> {
  List<MapSource> _customSources = [];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  void _loadSources() {
    setState(() {
      _customSources = widget.customWmsService.customSources;
    });
  }

  Future<void> _addSource() async {
    final source = await showDialog<MapSource>(
      context: context,
      builder: (ctx) => _WmsSourceDialog(),
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
    final hasSources = _customSources.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Custom WMS Sources',
            style: TextStyle(color: Colors.white70)),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white70),
            tooltip: 'Add custom WMS',
            onPressed: _addSource,
          ),
        ],
      ),
      body: !hasSources
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers_outlined,
                        color: Colors.white24, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'No custom WMS sources',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your own WMS endpoints for orthophotos, '
                      'hillshades, or other map layers.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _addSource,
                      icon: const Icon(Icons.add),
                      label: const Text('Add WMS Source'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: _customSources.length,
              itemBuilder: (ctx, i) => _CustomWmsListItem(
                source: _customSources[i],
                onEdit: () => _editSource(_customSources[i]),
                onDelete: () => _deleteSource(_customSources[i]),
              ),
            ),
    );
  }
}

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
  int _tileSize = 256;

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
    _tileSize = existing?.tileSize ?? 256;
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
    // Validation
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

    // Ensure ID is URL-safe (lowercase, alphanumeric + underscore/dash)
    final id = _idController.text.trim().toLowerCase().replaceAll(' ', '_');
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) {
      _showError('ID can only contain lowercase letters, numbers, hyphens, and underscores');
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
              enabled: !isEditing, // Can't change ID when editing
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
              hint: '© Data Provider',
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
