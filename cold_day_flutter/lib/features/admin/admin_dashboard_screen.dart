import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _kpis = {};
  bool _loading = true;
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
      final kpis = await ApiClient.fetchAdminKpis();
      if (!mounted) return;
      setState(() {
        _kpis = kpis;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar los KPIs: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final clients = _kpis['total_clients'] as int? ?? 0;
    final technicians = _kpis['total_technicians'] as int? ?? 0;
    final pending = _kpis['pending_technicians'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen KPIs'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Clientes',
                  value: '$clients',
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: 'Técnicos',
                  value: '$technicians',
                  icon: Icons.handyman,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: 'Pendientes',
                  value: '$pending',
                  icon: Icons.hourglass_top,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Desglose de solicitudes por estado',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _StatusBreakdown(
            byStatus: (_kpis['requests_by_status'] as Map<String, dynamic>?) ?? const {},
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111928) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  final Map<String, dynamic> byStatus;

  const _StatusBreakdown({required this.byStatus});

  @override
  Widget build(BuildContext context) {
    final entries = byStatus.entries.where((e) => (e.value as int? ?? 0) > 0);
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No hay solicitudes registradas.')),
      );
    }
    return Column(
      children: [
        for (final entry in entries)
          ListTile(
            leading: const Icon(Icons.assignment),
            title: Text(requestStatusLabel(entry.key)),
            trailing: Text(
              '${entry.value}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
      ],
    );
  }
}

// ─── ADMIN: LISTA DE GESTION DE TECNICOS ──────────────────────────────────────
class AdminTechniciansListScreen extends StatefulWidget {
  final bool showPendingOnly;

  const AdminTechniciansListScreen({super.key, required this.showPendingOnly});

  @override
  State<AdminTechniciansListScreen> createState() => _AdminTechniciansListScreenState();
}

class _AdminTechniciansListScreenState extends State<AdminTechniciansListScreen> {
  List<Map<String, dynamic>> _technicians = [];
  bool _loading = true;
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
      final techs = await ApiClient.fetchAdminTechnicians();
      if (!mounted) return;
      setState(() {
        if (widget.showPendingOnly) {
          _technicians = techs.where((t) => t['verification_status'] == 'pending').toList();
        } else {
          _technicians = techs.where((t) => t['verification_status'] != 'pending').toList();
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar técnicos';
        _loading = false;
      });
    }
  }

  Future<void> _approve(int id) async {
    try {
      await ApiClient.verifyTechnician(id);
      _load();
    } catch (_) {}
  }

  Future<void> _reject(int id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar técnico'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Motivo del rechazo'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await ApiClient.rejectTechnician(id, reason);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_technicians.isEmpty) {
      return const Center(child: Text('No hay técnicos en esta sección.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _technicians.length,
      itemBuilder: (context, index) {
        final tech = _technicians[index];
        final name = tech['name'] as String;
        final specialty = tech['specialty'] as String? ?? 'Técnico';
        final status = tech['verification_status'] as String;
        final id = tech['id'] as int;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      status == 'verified' ? 'Verificado ✅' : status == 'rejected' ? 'Rechazado ❌' : 'Pendiente ⏳',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Text(specialty, style: const TextStyle(color: Colors.grey)),
                if (status == 'pending') ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _reject(id),
                        child: const Text('Rechazar', style: TextStyle(color: Colors.red)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _approve(id),
                        child: const Text('Aprobar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}