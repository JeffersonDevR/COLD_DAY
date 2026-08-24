import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';

class ServiceConfigScreen extends StatefulWidget {
  const ServiceConfigScreen({super.key});
  @override
  State<ServiceConfigScreen> createState() => _ServiceConfigScreenState();
}

class _ServiceConfigScreenState extends State<ServiceConfigScreen> {
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;
  int? _busyCategory;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        ApiClient.fetchCatalog(),
        ApiClient.fetchMyServices(),
      ]);
      if (mounted)
        setState(() {
          _catalog = result[0] as List<Map<String, dynamic>>;
          _services = result[1] as List<Map<String, dynamic>>;
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = ApiClient.userFacingError(
            error,
            action: 'cargar tus servicios',
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configure(
    Map<String, dynamic> category,
    Map<String, dynamic>? existing,
  ) async {
    final types =
        ((existing?['service_types'] as List?)?.whereType<String>().toList() ??
        ['repair']);
    var sector = existing?['sector'] as String? ?? 'both';
    final selected = await showDialog<List<dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Configurar ${category['name'] ?? 'servicio'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in const {
                'repair': 'Reparación',
                'maintenance': 'Mantenimiento',
                'installation': 'Instalación',
              }.entries)
                CheckboxListTile(
                  value: types.contains(item.key),
                  title: Text(item.value),
                  onChanged: (value) => setDialogState(() {
                    if (value == true)
                      types.add(item.key);
                    else if (types.length > 1)
                      types.remove(item.key);
                  }),
                ),
              DropdownButtonFormField<String>(
                value: sector,
                decoration: const InputDecoration(labelText: 'Sector'),
                items: const [
                  DropdownMenuItem(
                    value: 'residential',
                    child: Text('Residencial'),
                  ),
                  DropdownMenuItem(
                    value: 'industrial',
                    child: Text('Industrial'),
                  ),
                  DropdownMenuItem(value: 'both', child: Text('Ambos')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => sector = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [types, sector]),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final selectedTypes = (selected[0] as List).whereType<String>().toList();
    final selectedSector = selected[1] as String;
    final categoryId = category['id'] as int;
    setState(() => _busyCategory = categoryId);
    try {
      if (existing != null)
        await ApiClient.removeMyService(existing['id'] as int);
      await ApiClient.addMyService(
        categoryId: categoryId,
        serviceTypes: selectedTypes,
        sector: selectedSector,
      );
      _message('Configuración guardada');
      await _load();
    } catch (error) {
      _message(
        ApiClient.userFacingError(error, action: 'guardar la configuración'),
      );
    } finally {
      if (mounted) setState(() => _busyCategory = null);
    }
  }

  Future<void> _remove(Map<String, dynamic> service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar servicio'),
        content: const Text('¿Querés quitar esta categoría de tu perfil?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busyCategory = service['category_id'] as int?);
    try {
      await ApiClient.removeMyService(service['id'] as int);
      _message('Servicio eliminado');
      await _load();
    } catch (error) {
      _message(
        ApiClient.userFacingError(error, action: 'eliminar el servicio'),
      );
    } finally {
      if (mounted) setState(() => _busyCategory = null);
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis servicios')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? AsyncStateView(message: _error!, action: _load)
        : _catalog.isEmpty
        ? const Center(child: Text('No hay categorías disponibles'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: _catalog.map((category) {
              final id = category['id'] as int?;
              final matches = _services
                  .where((service) => service['category_id'] == id)
                  .toList();
              final existing = matches.isEmpty ? null : matches.first;
              return _CategoryCard(
                category: category,
                existing: existing,
                busy: id == _busyCategory,
                onConfigure: () => _configure(category, existing),
                onRemove: existing == null ? null : () => _remove(existing),
              );
            }).toList(),
          ),
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.existing,
    required this.busy,
    required this.onConfigure,
    required this.onRemove,
  });
  final Map<String, dynamic> category;
  final Map<String, dynamic>? existing;
  final bool busy;
  final VoidCallback onConfigure;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category['name'] as String? ?? 'Categoría',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Switch(
              value: existing != null,
              onChanged: busy
                  ? null
                  : (_) => existing == null ? onConfigure() : onRemove?.call(),
            ),
          ],
        ),
        if (existing != null) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                ((existing!['service_types'] as List?)?.whereType<String>() ??
                        const <String>[])
                    .map((type) => Chip(label: Text(_typeLabel(type))))
                    .toList(),
          ),
          const SizedBox(height: 8),
          Text('Sector: ${_sectorLabel(existing!['sector'] as String?)}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onConfigure,
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar servicio',
              ),
            ],
          ),
        ] else
          Text('Activá esta categoría para elegir tipos de servicio y sector.'),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}

String _typeLabel(String type) =>
    {
      'repair': 'Reparación',
      'maintenance': 'Mantenimiento',
      'installation': 'Instalación',
    }[type] ??
    type;
String _sectorLabel(String? sector) =>
    {
      'residential': 'Residencial',
      'industrial': 'Industrial',
      'both': 'Ambos',
    }[sector] ??
    'No definido';
