import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/pact_review_dialog.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';

/// Historial del cliente (RF-SR-010, HU-SR-001/003): listado propio desde
/// GET /api/services/my; el detalle muestra la línea de tiempo (bids + pactos)
/// y las acciones según el estado: aceptar oferta, aceptar/rechazar pacto
/// (PactReviewDialog) y cancelar la solicitud.
class ClientHistoryScreen extends StatefulWidget {
  const ClientHistoryScreen({super.key});

  @override
  State<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends State<ClientHistoryScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await ApiClient.fetchMyRequests();
      if (!mounted) return;
      setState(() => _requests = requests);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el historial: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openDetail(Map<String, dynamic> summary) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _RequestDetailScreen(
          requestId: summary['id'] as int,
          summary: summary,
        ),
      ),
    );
    if (changed == true) {
      _showMessage('Solicitud actualizada');
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Historial'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar historial',
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
            Text('Cargando historial...'),
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
                onPressed: _loadHistory,
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
            Icon(Icons.history, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Aún no tienes solicitudes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Creá una desde el flujo de solicitud',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final req = _requests[index];
        final status = req['status'] as String? ?? '';
        final technician = req['technician'] as Map<String, dynamic>?;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openDetail(req),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          req['equipment'] as String? ?? 'Solicitud',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(requestStatusLabel(status)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.blue.shade50,
                      ),
                    ],
                  ),
                  if ((req['description'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text(
                      req['description'] as String,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        formatRequestDate(req['created_at'] as String?),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      if (technician != null) ...[
                        const Icon(Icons.engineering,
                            size: 14, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          technician['name'] as String? ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Detalle de una solicitud: estado, técnico asignado y línea de tiempo
/// (bids + pactos) con las acciones disponibles según el estado.
class _RequestDetailScreen extends StatefulWidget {
  final int requestId;
  final Map<String, dynamic> summary;

  const _RequestDetailScreen({required this.requestId, required this.summary});

  @override
  State<_RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<_RequestDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ApiClient.fetchServiceRequestDetail(widget.requestId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el detalle: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _acceptBid(Map<String, dynamic> bid) async {
    try {
      final result = await ApiClient.acceptBid(
        requestId: widget.requestId,
        bidId: bid['id'] as int,
      );
      _showMessage(result['message'] as String? ?? 'Oferta aceptada');
      _loadDetail();
    } catch (e) {
      _showMessage('Error al aceptar la oferta: $e');
    }
  }

  Future<void> _reviewPact(Map<String, dynamic> pact) async {
    final decision = await PactReviewDialog.show(
      context,
      agreement: pact,
    );
    if (decision == null || !mounted) return;

    try {
      final result = decision == PactReviewDecision.accept
          ? await ApiClient.acceptAgreement(
              requestId: widget.requestId,
              agreementId: pact['id'] as int,
            )
          : await ApiClient.rejectAgreement(
              requestId: widget.requestId,
              agreementId: pact['id'] as int,
            );
      _showMessage(result['message'] as String? ?? 'Pacto actualizado');
      _loadDetail();
    } catch (e) {
      _showMessage('Error al procesar el pacto: $e');
    }
  }

  Future<void> _cancelRequest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: const Text('¿Cancelar la solicitud?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final result = await ApiClient.cancelServiceRequest(
        requestId: widget.requestId,
      );
      if (!mounted) return;
      _showMessage(result['message'] as String? ?? 'Solicitud cancelada');
      Navigator.pop(context, true);
    } catch (e) {
      _showMessage('Error al cancelar la solicitud: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Solicitud #${widget.requestId}'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
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
      return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadDetail,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final status = detail['status'] as String? ?? '';
    final technician = detail['technician'] as Map<String, dynamic>?;
    final timeline = detail['timeline'] as Map<String, dynamic>? ?? {};
    final bids = (timeline['bids'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final pacts = (timeline['agreements'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (detail['equipment'] as Map<String, dynamic>?)?['name']
                                as String? ??
                            'Solicitud',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(requestStatusLabel(status)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.blue.shade50,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  detail['description'] as String? ?? '',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Text(
                  'Creada: ${formatRequestDate(detail['created_at'] as String?)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                // RF-SR-004/005: las observaciones del diagnóstico son parte
                // del vertical del pacto y quedan visibles en el detalle.
                if ((detail['diagnosis_observations'] as String?)
                        ?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Diagnóstico: ${detail['diagnosis_observations']}',
                    style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                ],
                if (technician != null) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.engineering, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Text(
                        '${technician['name']} '
                        '(${technician['specialty']}) ⭐ ${technician['rating']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // ===== Acciones según estado =====
        if (status == 'requested' || status == 'bidding') ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _cancelRequest,
              icon: const Icon(Icons.cancel),
              label: const Text('Cancelar solicitud'),
            ),
          ),
        ],

        // ===== Línea de tiempo: ofertas =====
        const SizedBox(height: 16),
        const Text(
          'Ofertas recibidas',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (bids.isEmpty)
          const Text('Sin ofertas todavía', style: TextStyle(color: Colors.grey)),
        ...bids.map((bid) => _BidTile(
              bid: bid,
              showAccept: status == 'bidding' && bid['status'] == 'pending',
              onAccept: () => _acceptBid(bid),
            )),

        // ===== Línea de tiempo: pactos =====
        const SizedBox(height: 16),
        const Text(
          'Pactos de servicio',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (pacts.isEmpty)
          const Text('Sin pactos todavía', style: TextStyle(color: Colors.grey)),
        ...pacts.map((pact) => _PactTile(
              pact: pact,
              showReview: status == 'pact_proposed' && pact['status'] == 'proposed',
              onReview: () => _reviewPact(pact),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _BidTile extends StatelessWidget {
  final Map<String, dynamic> bid;
  final bool showAccept;
  final VoidCallback onAccept;

  const _BidTile({
    required this.bid,
    required this.showAccept,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final transport = (bid['transport_cost'] as num?)?.toDouble() ?? 0;
    final diagnosis = (bid['diagnosis_cost'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bid['technician_name'] as String? ?? 'Técnico',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Traslado ${formatCop(transport)} · '
                    'Diagnóstico ${formatCop(diagnosis)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (showAccept)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                ),
                onPressed: onAccept,
                child: const Text('Aceptar oferta'),
              )
            else
              Text(
                _bidStatusLabel(bid['status'] as String? ?? ''),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  String _bidStatusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Aceptada';
      case 'rejected':
        return 'Rechazada';
      default:
        return 'Pendiente';
    }
  }
}

class _PactTile extends StatelessWidget {
  final Map<String, dynamic> pact;
  final bool showReview;
  final VoidCallback onReview;

  const _PactTile({
    required this.pact,
    required this.showReview,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final total = (pact['total'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pacto de servicio',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    formatCop(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.blueAccent,
                    ),
                  ),
                  Text(
                    _pactStatusLabel(pact['status'] as String? ?? ''),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (showReview)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                ),
                onPressed: onReview,
                child: const Text('Revisar pacto'),
              ),
          ],
        ),
      ),
    );
  }

  String _pactStatusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Aceptado';
      case 'rejected':
        return 'Rechazado';
      default:
        return 'Propuesto';
    }
  }
}