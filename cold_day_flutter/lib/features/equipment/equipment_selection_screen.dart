import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
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
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
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
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3F2FD), Colors.white],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
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
          Row(
            children: [
              Expanded(
                child: _TechnologyCard(
                  icon: Icons.settings_backup_restore,
                  label: 'Convencional',
                  selected: _selectedTechnology == 'conventional',
                  onTap: () => setState(() => _selectedTechnology = 'conventional'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnologyCard(
                  icon: Icons.bolt,
                  label: 'Inverter',
                  selected: _selectedTechnology == 'inverter',
                  onTap: () => setState(() => _selectedTechnology = 'inverter'),
                ),
              ),
            ],
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
              style: TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
          ],
        ],

        const SizedBox(height: 28),

        // ===== Continuar a confirmación =====
        if (_selectedSector != null)
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueAccent,
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
                    _selectedCategory![_selectedSector!] as List<dynamic>? ?? [];
                if (equipments.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No hay equipos disponibles para este sector'),
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
                      sector: _selectedSector!,
                      equipmentType: first['name'] as String,
                      serviceType: 'repair',
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
          backgroundColor: Colors.blueAccent,
          child: Text(
            num,
            style: const TextStyle(
              color: Colors.white,
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
          color: selected ? Colors.blueAccent : Colors.white,
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: selected ? Colors.white : Colors.blueGrey),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.blueGrey,
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
          color: selected ? Colors.blueAccent : Colors.white,
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? Colors.white : Colors.blueGrey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.blueGrey,
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
              ? Colors.grey.shade100
              : selected
                  ? Colors.blueAccent
                  : Colors.white,
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 36,
              color: !enabled
                  ? Colors.grey.shade400
                  : selected
                      ? Colors.white
                      : Colors.blueGrey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: !enabled
                    ? Colors.grey.shade400
                    : selected
                        ? Colors.white
                        : Colors.blueGrey,
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