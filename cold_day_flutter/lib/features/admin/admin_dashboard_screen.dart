import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';
import 'package:cold_day_flutter/core/theme/app_theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _kpis = {};
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _technicians = [];
  final Set<int> _mutatingTechnicians = {};

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
      setState(() => _error = 'No se pudo cargar los KPIs: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approveTechnician(int id) async {
    setState(() => _mutatingTechnicians.add(id));
    try {
      await ApiClient.verifyTechnician(id);
      if (mounted) _showMessage('Técnico verificado');
      await _load();
    } catch (error) {
      if (mounted)
        _showMessage(
          ApiClient.userFacingError(error, action: 'verificar al técnico'),
        );
    } finally {
      if (mounted) setState(() => _mutatingTechnicians.remove(id));
    }
  }

  Future<void> _rejectTechnician(int id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Rechazar técnico'),
          content: TextField(
            key: const Key('reject-reason'),
            controller: controller,
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(labelText: 'Motivo del rechazo'),
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
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _mutatingTechnicians.add(id));
    try {
      await ApiClient.rejectTechnician(id, reason);
      if (mounted) _showMessage('Técnico rechazado');
      await _load();
    } catch (error) {
      if (mounted)
        _showMessage(
          ApiClient.userFacingError(error, action: 'rechazar al técnico'),
        );
    } finally {
      if (mounted) setState(() => _mutatingTechnicians.remove(id));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 3 : 1;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - AppSpacing.sm * 2) / columns;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: width,
                      child: _KpiCard(
                        label: 'Clientes',
                        value: '$clients',
                        icon: Icons.people,
                        color: Theme.of(context).colorScheme.primary,
                        valueKey: const Key('kpi-clients'),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _KpiCard(
                        label: 'Técnicos',
                        value: '$technicians',
                        icon: Icons.handyman,
                        color: Theme.of(context).colorScheme.tertiary,
                        valueKey: const Key('kpi-technicians'),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _KpiCard(
                        label: 'Pendientes',
                        value: '$pending',
                        icon: Icons.hourglass_top,
                        color: Theme.of(context).colorScheme.secondary,
                        valueKey: const Key('kpi-pending'),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_technicians.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(
                title: 'Técnicos',
                subtitle: 'Estado de verificación',
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._technicians.map(
                (tech) => _TechnicianSummary(
                  technician: tech,
                  busy: _mutatingTechnicians.contains(tech['id']),
                  onApprove: () => _approveTechnician(tech['id'] as int),
                  onReject: () => _rejectTechnician(tech['id'] as int),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Desglose de solicitudes por estado',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            _StatusBreakdown(
              byStatus:
                  (_kpis['requests_by_status'] as Map<String, dynamic>?) ??
                  const {},
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Key? valueKey;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            key: valueKey,
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
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
            title: Text('${requestStatusLabel(entry.key)} (${entry.value})'),
            trailing: StatusBadge(
              label: requestStatusLabel(entry.key),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
    );
  }
}

class _TechnicianSummary extends StatelessWidget {
  const _TechnicianSummary({
    required this.technician,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> technician;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final status = technician['verification_status'] as String? ?? 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    technician['name'] as String? ?? 'Técnico',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(
                  label: status == 'verified'
                      ? 'Verificado'
                      : status == 'rejected'
                      ? 'Rechazado'
                      : 'Pendiente',
                ),
              ],
            ),
            if (status == 'pending')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : onReject,
                    child: const Text('Rechazar'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : onApprove,
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Aprobar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── ADMIN: LISTA DE GESTION DE TECNICOS ──────────────────────────────────────
class AdminTechniciansListScreen extends StatefulWidget {
  final bool showPendingOnly;

  const AdminTechniciansListScreen({super.key, required this.showPendingOnly});

  @override
  State<AdminTechniciansListScreen> createState() =>
      _AdminTechniciansListScreenState();
}

class _AdminTechniciansListScreenState
    extends State<AdminTechniciansListScreen> {
  List<Map<String, dynamic>> _technicians = [];
  bool _loading = true;
  String? _error;
  final Set<int> _mutating = {};

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
          _technicians = techs
              .where((t) => t['verification_status'] == 'pending')
              .toList();
        } else {
          _technicians = techs
              .where((t) => t['verification_status'] != 'pending')
              .toList();
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
    setState(() => _mutating.add(id));
    try {
      await ApiClient.verifyTechnician(id);
      if (mounted) _showMessage('Técnico verificado');
      await _load();
    } catch (error) {
      if (mounted)
        _showMessage(
          ApiClient.userFacingError(error, action: 'verificar al técnico'),
        );
    } finally {
      if (mounted) setState(() => _mutating.remove(id));
    }
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    setState(() => _mutating.add(id));
    try {
      await ApiClient.rejectTechnician(id, reason);
      if (mounted) _showMessage('Técnico rechazado');
      await _load();
    } catch (error) {
      if (mounted)
        _showMessage(
          ApiClient.userFacingError(error, action: 'rechazar al técnico'),
        );
    } finally {
      if (mounted) setState(() => _mutating.remove(id));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

        return AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    StatusBadge(
                      label: status == 'verified'
                          ? 'Verificado'
                          : status == 'rejected'
                          ? 'Rechazado'
                          : 'Pendiente',
                    ),
                  ],
                ),
                Text(
                  specialty,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (status == 'pending') ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _mutating.contains(id)
                            ? null
                            : () => _reject(id),
                        child: const Text('Rechazar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _mutating.contains(id)
                            ? null
                            : () => _approve(id),
                        child: _mutating.contains(id)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Aprobar'),
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
