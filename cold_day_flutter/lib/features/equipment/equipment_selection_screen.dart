import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/request/client_history_screen.dart';
import 'package:cold_day_flutter/features/request/service_request_screen.dart';

/// Flujo de solicitud de servicio (flujo Luis Santander):
/// categoría -> tecnología (si aplica) -> sector (Residencial/Industrial)
/// -> Solicitud (RF-LAND-005: sin dead-end estático).
class EquipmentSelectionScreen extends StatefulWidget {
  const EquipmentSelectionScreen({super.key});

  @override
  State<EquipmentSelectionScreen> createState() =>
      _EquipmentSelectionScreenState();
}

class _EquipmentSelectionScreenState extends State<EquipmentSelectionScreen> {
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;

  // Selección actual
  Map<String, dynamic>? _selectedCategory;
  String? _selectedTechnology; // 'conventional' o 'inverter' (solo si aplica)
  String? _selectedSector; // 'residential' o 'industrial'

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await ApiClient.fetchCatalog();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el catálogo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Iconos mapeados desde el nombre que viene de la DB
  IconData _iconFor(String? name) {
    switch (name) {
      case 'kitchen':
        return Icons.kitchen;
      case 'snow':
        return Icons.ac_unit;
      case 'air_wave':
        return Icons.air;
      case 'laundry':
        return Icons.local_laundry_service;
      case 'electricity':
        return Icons.bolt;
      case 'devices':
        return Icons.devices_other;
      case 'videocam':
        return Icons.videocam;
      default:
        return Icons.devices_other;
    }
  }

  List<String> _technologiesOf(Map<String, dynamic> cat) {
    final t = cat['technologies'] as List<dynamic>? ?? [];
    return t.map((e) => e as String).toList();
  }

  bool _hasSector(String sector) {
    final list = _selectedCategory?[sector] as List<dynamic>? ?? [];
    return list.isNotEmpty;
  }

  void _selectCategory(Map<String, dynamic> cat) {
    setState(() {
      _selectedCategory = cat;
      _selectedTechnology = null;
      _selectedSector = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Qué necesitas?'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        centerTitle: true,
        actions: [
          // RF-SR-010: el historial del cliente es alcanzable desde el flujo.
          IconButton(
            tooltip: 'Mi historial',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClientHistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final refresh = await TokenStore.readRefreshToken();
              if (refresh != null) {
                try {
                  await ApiClient.logout(refresh);
                } catch (_) {}
              }
              await TokenStore.clear();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surfaceContainerLow,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: 16),
            Text('Cargando catálogo...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ===== Paso 1: Categoría =====
        _stepHeader('1', 'Tipo de equipo'),
        const SizedBox(height: 12),
        _categories.isEmpty
            ? const Text('Catálogo vacío')
            : Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _categories.map((cat) {
                  final selected = _selectedCategory?['id'] == cat['id'];
                  return _CategoryChip(
                    icon: _iconFor(cat['icon'] as String?),
                    label: cat['name'] as String,
                    selected: selected,
                    onTap: () => _selectCategory(cat),
                  );
                }).toList(),
              ),

        // ===== Paso 2: Tecnología (solo si la categoría la tiene) =====
        if (_selectedCategory != null &&
            _technologiesOf(_selectedCategory!).isNotEmpty) ...[
          const SizedBox(height: 24),
          _stepHeader('2', 'Tecnología'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _technologiesOf(_selectedCategory!).map((technology) {
              final label = technology == 'inverter'
                  ? 'Inverter'
                  : 'Convencional';
              return SizedBox(
                width: 170,
                child: _TechnologyCard(
                  icon: technology == 'inverter'
                      ? Icons.bolt
                      : Icons.settings_backup_restore,
                  label: label,
                  selected: _selectedTechnology == technology,
                  onTap: () => setState(() => _selectedTechnology = technology),
                ),
              );
            }).toList(),
          ),
        ],

        // ===== Paso 3: Sector (solo si hay categoría) =====
        if (_selectedCategory != null) ...[
          const SizedBox(height: 24),
          _stepHeader(
            _technologiesOf(_selectedCategory!).isEmpty ? '2' : '3',
            'Sector',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SectorCard(
                  icon: Icons.home_work,
                  label: 'Residencial',
                  selected: _selectedSector == 'residential',
                  enabled: _hasSector('residential'),
                  onTap: () => setState(() => _selectedSector = 'residential'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SectorCard(
                  icon: Icons.factory,
                  label: 'Industrial',
                  selected: _selectedSector == 'industrial',
                  enabled: _hasSector('industrial'),
                  onTap: () => setState(() => _selectedSector = 'industrial'),
                ),
              ),
            ],
          ),
          if (!_hasSector('residential') && _hasSector('industrial')) ...[
            const SizedBox(height: 8),
            const Text(
              'Este servicio aplica solo para sector Industrial',
              style: TextStyle(color: Color(0xFF3F4A46), fontSize: 12),
            ),
          ],
        ],

        const SizedBox(height: 28),

        // ===== Continuar a confirmación =====
        if (_selectedSector != null &&
            (_technologiesOf(_selectedCategory!).isEmpty ||
                _selectedTechnology != null))
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text(
                'Continuar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                // RF-LAND-005: Continúa a la creación de la solicitud real,
                // no al dead-end estático de confirmación.
                final equipments =
                    _selectedCategory![_selectedSector!] as List<dynamic>? ??
                    [];
                if (equipments.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No hay equipos disponibles para este sector',
                      ),
                    ),
                  );
                  return;
                }
                final first = equipments.first as Map<String, dynamic>;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ServiceRequestScreen(
                      equipmentId: first['id'] as int,
                      categoryHint: _selectedCategory!['name'] as String,
                      sector: _selectedSector!,
                      equipmentType: first['name'] as String,
                      serviceType: 'repair',
                      technology: _selectedTechnology,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _stepHeader(String num, String title) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            num,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechnologyCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TechnologyCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectorCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _SectorCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: !enabled
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 36,
              color: !enabled
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: !enabled
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(height: 4),
              const Text(
                'No disponible',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
