import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';
import 'package:cold_day_flutter/features/technician/bid_submission_screen.dart';
import 'package:cold_day_flutter/features/technician/diagnosis_screen.dart';
import 'package:cold_day_flutter/features/technician/pact_proposal_screen.dart';
import 'package:cold_day_flutter/features/technician/service_config_screen.dart';
import 'package:cold_day_flutter/features/radar/technician_map_screen.dart';

/// Dashboard del técnico (HU-SR-002): radar real de solicitudes cercanas
/// (RF-MATCH-004) con acciones según el estado de cada solicitud:
/// ofertar (requested/bidding sin bid), registrar diagnóstico (diagnosis),
/// proponer pacto (pact_proposed) y finalizar servicio (in_progress).
class TechnicianDashboard extends StatefulWidget {
  const TechnicianDashboard({super.key});

  @override
  State<TechnicianDashboard> createState() => _TechnicianDashboardState();
}

class _TechnicianDashboardState extends State<TechnicianDashboard> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRadar();
  }

  Future<void> _loadRadar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await ApiClient.fetchTechnicianRadar();
      if (!mounted) return;
      setState(() => _requests = requests);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el radar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openOffer(Map<String, dynamic> request) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => BidSubmissionScreen(
          requestId: request['id'] as int,
          equipment: request['equipment'] as String? ?? 'Solicitud',
        ),
      ),
    );
    if (submitted == true) {
      _showMessage('¡Oferta enviada!');
      _loadRadar();
    }
  }

  Future<void> _openDiagnosis(Map<String, dynamic> request) async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DiagnosisScreen(requestId: request['id'] as int),
      ),
    );
    if (done == true) {
      _showMessage('Diagnóstico registrado');
      _loadRadar();
    }
  }

  Future<void> _openPact(Map<String, dynamic> request) async {
    final proposed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PactProposalScreen(requestId: request['id'] as int),
      ),
    );
    if (proposed == true) {
      _showMessage('Pacto de servicio propuesto al cliente');
      _loadRadar();
    }
  }

  Future<void> _complete(Map<String, dynamic> request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar servicio'),
        content: const Text('¿Finalizar el servicio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ApiClient.completeServiceRequest(requestId: request['id'] as int);
      _showMessage('Servicio completado');
      _loadRadar();
    } catch (e) {
      _showMessage('Error al finalizar el servicio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar de Solicitudes'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ServiceConfigScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Mis servicios',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TechnicianMapScreen()),
            ),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Ver mapa',
          ),
          IconButton(
            onPressed: _loading ? null : _loadRadar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar radar',
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
            Text('Cargando solicitudes cercanas...'),
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
                onPressed: _loadRadar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.radar, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No hay solicitudes cercanas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Las nuevas solicitudes aparecen aquí',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _requests.length,
      itemBuilder: (context, index) => _RequestCard(
        request: _requests[index],
        onOffer: () => _openOffer(_requests[index]),
        onDiagnosis: () => _openDiagnosis(_requests[index]),
        onPact: () => _openPact(_requests[index]),
        onComplete: () => _complete(_requests[index]),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onOffer;
  final VoidCallback onDiagnosis;
  final VoidCallback onPact;
  final VoidCallback onComplete;

  const _RequestCard({
    required this.request,
    required this.onOffer,
    required this.onDiagnosis,
    required this.onPact,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final id = request['id'] as int;
    final status = request['status'] as String;
    final myBidStatus = request['my_bid_status'] as String?;
    final equipment = request['equipment'] as String? ?? 'Solicitud';
    final description = request['description'] as String? ?? '';

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
                  backgroundColor: Colors.blueAccent,
                  child: Text(
                    '#$id',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
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
                        equipment,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        requestStatusLabel(status),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description, style: const TextStyle(color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            Text(
              'Lat: ${request['latitude']}, Lon: ${request['longitude']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildAction(context, status, myBidStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    String status,
    String? myBidStatus,
  ) {
    // Oferta ya enviada: no se permite duplicar (RF-MATCH-005).
    if (myBidStatus == 'pending') {
      return const Chip(
        avatar: Icon(Icons.hourglass_top, size: 18),
        label: Text('Oferta enviada'),
        backgroundColor: Colors.amber,
      );
    }

    switch (status) {
      case 'requested':
      case 'bidding':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onOffer,
            icon: const Icon(Icons.handshake),
            label: const Text('Enviar oferta'),
          ),
        );
      case 'diagnosis':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onDiagnosis,
            icon: const Icon(Icons.assignment_turned_in),
            label: const Text('Registrar diagnóstico'),
          ),
        );
      case 'pact_proposed':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onPact,
            icon: const Icon(Icons.description),
            label: const Text('Proponer pacto'),
          ),
        );
      case 'in_progress':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onComplete,
            icon: const Icon(Icons.check_circle),
            label: const Text('Finalizar servicio'),
          ),
        );
      default:
        // completed / cancelled: estado terminal, sin acción.
        return const SizedBox.shrink();
    }
  }
}
