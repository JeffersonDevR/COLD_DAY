import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';

/// Dashboard de administración (HU-ADM-001/002, RF-ADM-001..008).
///
/// Mínimo del piloto: KPIs de un vistazo (clientes, técnicos, pendientes y
/// desglose de solicitudes por estado) + cola de verificación de técnicos
/// con aprobar/rechazar (motivo obligatorio en el rechazo).
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _kpis = {};
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
      final kpis = await ApiClient.fetchAdminKpis();
      final technicians = await ApiClient.fetchAdminTechnicians();
      if (!mounted) return;
      setState(() {
        _kpis = kpis;
        _technicians = technicians;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el panel: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _approve(Map<String, dynamic> technician) async {
    try {
      await ApiClient.verifyTechnician(technician['id'] as int);
      _showMessage('Técnico verificado');
      _load();
    } catch (e) {
      _showMessage('Error al verificar: $e');
    }
  }

  Future<void> _reject(Map<String, dynamic> technician) async {
    final reason = await _confirmReject(technician['name'] as String? ?? '');
    if (reason == null || !mounted) return;
    try {
      await ApiClient.rejectTechnician(technician['id'] as int, reason);
      _showMessage('Técnico rechazado');
      _load();
    } catch (e) {
      _showMessage('Error al rechazar: $e');
    }
  }

  /// Diálogo de rechazo: el motivo es obligatorio (RF-TEC-003), el botón de
  /// confirmar queda deshabilitado mientras el campo esté vacío.
  Future<String?> _confirmReject(String name) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Rechazar técnico'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$name quedará rechazado del piloto.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('reject-reason'),
                controller: controller,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Motivo del rechazo (obligatorio)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Rechazar técnico'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar panel',
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
            Text('Cargando panel de administración...'),
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
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final pending = _technicians
        .where((t) => t['verification_status'] == 'pending')
        .toList();
    final others = _technicians
        .where((t) => t['verification_status'] != 'pending')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KpiRow(
          clients: _kpis['total_clients'] as int? ?? 0,
          technicians: _kpis['total_technicians'] as int? ?? 0,
          pending: _kpis['pending_technicians'] as int? ?? 0,
        ),
        const SizedBox(height: 16),
        _StatusBreakdown(
          byStatus: (_kpis['requests_by_status'] as Map<String, dynamic>?) ??
              const {},
        ),
        const SizedBox(height: 24),
        Text(
          'Cola de verificación (${pending.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay técnicos pendientes de verificación.'),
            ),
          )
        else
          ...pending.map(
            (t) => _QueueCard(
              technician: t,
              onApprove: () => _approve(t),
              onReject: () => _reject(t),
            ),
          ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Todos los técnicos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...others.map(_TechnicianStatusTile.new),
        ],
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  final int clients;
  final int technicians;
  final int pending;

  const _KpiRow({
    required this.clients,
    required this.technicians,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'Clientes',
            value: '$clients',
            icon: Icons.people,
            valueKey: const Key('kpi-clients'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            label: 'Técnicos',
            value: '$technicians',
            icon: Icons.handyman,
            valueKey: const Key('kpi-technicians'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            label: 'Pendientes',
            value: '$pending',
            icon: Icons.hourglass_top,
            valueKey: const Key('kpi-pending'),
            highlight: pending > 0,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Key valueKey;
  final bool highlight;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.valueKey,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: highlight ? Colors.amber.shade700 : Colors.blueAccent,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              key: valueKey,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No hay solicitudes registradas.'),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          Chip(
            avatar: const Icon(Icons.assignment, size: 18),
            label: Text('${requestStatusLabel(entry.key)} (${entry.value})'),
          ),
      ],
    );
  }
}

class _QueueCard extends StatelessWidget {
  final Map<String, dynamic> technician;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _QueueCard({
    required this.technician,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final name = technician['name'] as String? ?? 'Técnico';
    final specialty = technician['specialty'] as String? ?? 'Sin especialidad';
    final id = technician['id'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.amber.shade100,
                  child: Text(
                    '#$id',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.brown,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        specialty,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Aprobar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onReject,
                    icon: const Icon(Icons.block),
                    label: const Text('Rechazar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TechnicianStatusTile extends StatelessWidget {
  final Map<String, dynamic> technician;

  const _TechnicianStatusTile(this.technician);

  @override
  Widget build(BuildContext context) {
    final status = technician['verification_status'] as String? ?? '';
    final color = switch (status) {
      'verified' => Colors.green,
      'rejected' => Colors.red,
      _ => Colors.amber,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.shade100,
        child: Icon(Icons.person, color: color.shade800),
      ),
      title: Text(technician['name'] as String? ?? 'Técnico'),
      subtitle: Text(technician['specialty'] as String? ?? ''),
      trailing: Chip(
        avatar: Icon(Icons.badge, size: 18, color: color),
        label: Text(status == 'verified'
            ? 'Verificado'
            : status == 'rejected'
                ? 'Rechazado'
                : 'Pendiente'),
      ),
    );
  }
}