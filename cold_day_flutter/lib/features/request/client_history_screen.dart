import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/ratings/rating_screen.dart';
import 'package:cold_day_flutter/features/request/pact_review_dialog.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';
import 'package:cold_day_flutter/features/tracking/tracking_screen.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';

/// Historial del cliente (RF-SR-010, HU-SR-001/003): listado propio desde
/// GET /api/services/my; el detalle muestra la línea de tiempo (bids + pactos)
/// y las acciones según el estado: aceptar oferta, aceptar/rechazar pacto
/// (PactReviewDialog) y cancelar la solicitud.
class ClientHistoryScreen extends StatefulWidget {
  final bool? filterActive;

  const ClientHistoryScreen({super.key, this.filterActive});

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
      var requests = await ApiClient.fetchMyRequests();

      // Aplicar filtro si se especifica
      if (widget.filterActive != null) {
        final activeStates = [
          'requested',
          'bidding',
          'accepted',
          'in_progress',
        ];
        if (widget.filterActive == true) {
          requests = requests
              .where((r) => activeStates.contains(r['status']))
              .toList();
        } else {
          requests = requests
              .where((r) => !activeStates.contains(r['status']))
              .toList();
        }
      }

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
      appBar: widget.filterActive != null
          ? null
          : AppBar(
              title: const Text('Mi Historial'),
              centerTitle: true,
              actions: [
                IconButton(
                  onPressed: _loading ? null : _loadHistory,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualizar historial',
                ),
              ],
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
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
              Icon(
                Icons.cloud_off,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: 12),
            Text(
              'Aún no tienes solicitudes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Creá una desde el flujo de solicitud',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openDetail(req),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          req['equipment'] as String? ?? 'Solicitud',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      StatusBadge(label: requestStatusLabel(status)),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatRequestDate(req['created_at'] as String?),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (technician != null) ...[
                        const Icon(
                          Icons.engineering,
                          size: 14,
                          color: Colors.blueGrey,
                        ),
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
  // S4 ratings: esta sesión ya calificó la solicitud -> se oculta la acción
  // (RF-RAT-007; el backend igual rechaza duplicados con 409, RF-RAT-004).
  bool _reviewed = false;
  String? _actionLoading;
  String? _actionError;

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
      final detail = await ApiClient.fetchServiceRequestDetail(
        widget.requestId,
      );
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
    if (_actionLoading != null) return;
    final bidId = _intValue(bid['id']);
    if (bidId == null) {
      setState(
        () => _actionError = 'La oferta no tiene un identificador válido.',
      );
      return;
    }
    setState(() {
      _actionLoading = 'bid:$bidId';
      _actionError = null;
    });
    try {
      final result = await ApiClient.acceptBid(
        requestId: widget.requestId,
        bidId: bidId,
      );
      _showMessage(result['message'] as String? ?? 'Oferta aceptada');
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        setState(
          () => _actionError = 'No se pudo aceptar la oferta. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = null);
    }
  }

  Future<void> _reviewPact(Map<String, dynamic> pact) async {
    final decision = await PactReviewDialog.show(context, agreement: pact);
    if (decision == null || !mounted) return;
    final agreementId = _intValue(pact['id']);
    if (agreementId == null) {
      setState(
        () => _actionError = 'El pacto no tiene un identificador válido.',
      );
      return;
    }
    setState(() {
      _actionLoading = 'pact:$agreementId';
      _actionError = null;
    });

    try {
      final result = decision == PactReviewDecision.accept
          ? await ApiClient.acceptAgreement(
              requestId: widget.requestId,
              agreementId: agreementId,
            )
          : await ApiClient.rejectAgreement(
              requestId: widget.requestId,
              agreementId: agreementId,
            );
      _showMessage(result['message'] as String? ?? 'Pacto actualizado');
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        setState(
          () => _actionError = 'No se pudo actualizar el pacto. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = null);
    }
  }

  /// S4 ratings (RF-RAT-007): el cliente dueño califica un servicio terminado.
  Future<void> _rateService() async {
    final technician = _mapValue(_detail?['technician']);
    final rated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RatingScreen(
          requestId: widget.requestId,
          technicianName: technician?['name'] as String?,
        ),
      ),
    );
    if (rated != true || !mounted) return;
    setState(() => _reviewed = true);
    _showMessage('Calificación registrada, ¡gracias!');
    _loadDetail();
  }

  Future<void> _cancelRequest() async {
    if (_actionLoading != null) return;
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

    setState(() {
      _actionLoading = 'cancel';
      _actionError = null;
    });
    try {
      final result = await ApiClient.cancelServiceRequest(
        requestId: widget.requestId,
      );
      if (!mounted) return;
      _showMessage(result['message'] as String? ?? 'Solicitud cancelada');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _actionError = 'No se pudo cancelar la solicitud. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading = null);
    }
  }

  int? _intValue(Object? value) =>
      value is int ? value : int.tryParse('$value');

  double? _doubleValue(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  Map<String, dynamic>? _mapValue(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  void _openTracking() {
    final detail = _detail!;
    final latitude = _doubleValue(detail['latitude']);
    final longitude = _doubleValue(detail['longitude']);
    if (latitude == null || longitude == null) {
      _showMessage('La ubicación del servicio no está disponible.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          requestId: widget.requestId,
          clientLat: latitude,
          clientLon: longitude,
          clientName: detail['client_name'] as String?,
          technicianName: detail['technician_name'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Solicitud #${widget.requestId}'),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
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
    final status = detail['status']?.toString() ?? '';
    final technician = _mapValue(detail['technician']);
    final timeline = _mapValue(detail['timeline']) ?? {};
    final bids =
        (timeline['bids'] is List ? timeline['bids'] as List : <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
    final pacts =
        (timeline['agreements'] is List
                ? timeline['agreements'] as List
                : <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
    final latitude = _doubleValue(detail['latitude']);
    final longitude = _doubleValue(detail['longitude']);
    final canTrack =
        status == 'in_progress' &&
        technician != null &&
        latitude != null &&
        longitude != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
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
                        _mapValue(detail['equipment'])?['name']?.toString() ??
                            detail['equipment']?.toString() ??
                            'Solicitud',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    StatusBadge(label: requestStatusLabel(status)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  detail['description'] as String? ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Creada: ${formatRequestDate(detail['created_at'] as String?)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                // RF-SR-004/005: las observaciones del diagnóstico son parte
                // del vertical del pacto y quedan visibles en el detalle.
                if ((detail['diagnosis_observations'] as String?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Diagnóstico: ${detail['diagnosis_observations']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (technician != null) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      Icon(
                        Icons.engineering,
                        color: Theme.of(context).colorScheme.primary,
                      ),
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
        if (canTrack) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openTracking,
              icon: const Icon(Icons.location_on),
              label: const Text('Ver ubicación del técnico'),
            ),
          ),
        ],
        if (status == 'requested' || status == 'bidding') ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _actionLoading == null ? _cancelRequest : null,
              icon: const Icon(Icons.cancel),
              label: _actionLoading == 'cancel'
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cancelar solicitud'),
            ),
          ),
        ],
        // S4 ratings (RF-RAT-007): calificar solo tras la finalización.
        if (status == 'completed' && !_reviewed) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _rateService,
              icon: const Icon(Icons.star),
              label: const Text('Calificar servicio'),
            ),
          ),
        ],

        if (_actionError != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_actionError!)),
              ],
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
          const Text(
            'Sin ofertas todavía',
            style: TextStyle(color: Colors.grey),
          ),
        ...bids.map(
          (bid) => _BidTile(
            bid: bid,
            showAccept: status == 'bidding' && bid['status'] == 'pending',
            loading: _actionLoading == 'bid:${_intValue(bid['id'])}',
            onAccept: () => _acceptBid(bid),
          ),
        ),

        // ===== Línea de tiempo: pactos =====
        const SizedBox(height: 16),
        const Text(
          'Pactos de servicio',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (pacts.isEmpty)
          const Text(
            'Sin pactos todavía',
            style: TextStyle(color: Colors.grey),
          ),
        ...pacts.map(
          (pact) => _PactTile(
            pact: pact,
            showReview:
                status == 'pact_proposed' && pact['status'] == 'proposed',
            loading: _actionLoading == 'pact:${_intValue(pact['id'])}',
            onReview: () => _reviewPact(pact),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _BidTile extends StatelessWidget {
  final Map<String, dynamic> bid;
  final bool showAccept;
  final bool loading;
  final VoidCallback onAccept;

  const _BidTile({
    required this.bid,
    required this.showAccept,
    this.loading = false,
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
                onPressed: loading ? null : onAccept,
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Aceptar oferta'),
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
  final bool loading;
  final VoidCallback onReview;

  const _PactTile({
    required this.pact,
    required this.showReview,
    this.loading = false,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
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
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                onPressed: loading ? null : onReview,
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Revisar pacto'),
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
