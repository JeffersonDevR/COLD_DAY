import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

class TechnicianRadarScreen extends StatefulWidget {
  final int requestId;
  final double latitude;
  final double longitude;

  const TechnicianRadarScreen({
    super.key,
    required this.requestId,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<TechnicianRadarScreen> createState() => _TechnicianRadarScreenState();
}

class _TechnicianRadarScreenState extends State<TechnicianRadarScreen> {
  List<Map<String, dynamic>> _technicians = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // RF-MATCH-006: el radar pega al endpoint real de técnicos cercanos.
      final technicians = await ApiClient.fetchNearbyRequests(
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      setState(() => _technicians = technicians);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudieron cargar los técnicos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendOffer(Map<String, dynamic> tech) async {
    // Diálogo de oferta con los costos del bid (RF-TEC-006, RF-SR-002):
    // traslado + diagnóstico, ambos >= 0.
    final transportController = TextEditingController(text: '15000');
    final diagnosisController = TextEditingController(text: '35000');

    final costs = await showDialog<List<double>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar oferta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Oferta para ${tech['name']}'),
            const SizedBox(height: 12),
            TextField(
              controller: transportController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Costo de traslado (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: diagnosisController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Costo de diagnóstico (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final transport = double.tryParse(transportController.text);
              final diagnosis = double.tryParse(diagnosisController.text);
              if (transport == null ||
                  transport < 0 ||
                  diagnosis == null ||
                  diagnosis < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Los costos deben ser números mayores o iguales a 0',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, [transport, diagnosis]);
            },
            child: const Text('Enviar oferta'),
          ),
        ],
      ),
    );

    if (costs == null || !mounted) return;

    final transport = costs[0];
    final diagnosis = costs[1];

    try {
      await ApiClient.sendTechnicianBid(
        serviceRequestId: widget.requestId,
        priceOffered: transport + diagnosis,
        estimatedTimeMinutes: 45,
        transportCost: transport,
        diagnosisCost: diagnosis,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.check_circle,
            color: Theme.of(ctx).colorScheme.tertiary,
            size: 48,
          ),
          title: const Text('¡Oferta enviada!'),
          content: Text(
            'Tu oferta para ${tech['name']} se envió: '
            '\$${transport.toStringAsFixed(0)} de traslado + '
            '\$${diagnosis.toStringAsFixed(0)} de diagnóstico.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(ctx);
              },
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al enviar la oferta: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Radar de Técnicos #${widget.requestId}'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.radar,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Técnicos certificados en climatización a menos de 5 km',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
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
            const SizedBox(height: 16),
            const Text('Buscando técnicos cercanos...'),
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
              const Text(
                'No se pudo conectar con el radar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadTechnicians,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_technicians.isEmpty) {
      // RF-MATCH-007: mensaje de área sin cobertura.
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radar,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: 12),
            Text(
              'No se encontraron técnicos en tu área',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Probá ampliando el radio de búsqueda',
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
      itemCount: _technicians.length,
      itemBuilder: (context, index) {
        final tech = _technicians[index];
        final rating = (tech['rating'] as num).toDouble();
        final distance = (tech['distance_km'] as num).toDouble();
        final name = tech['name'] as String;
        final specialty = tech['specialty'] as String? ?? 'Técnico certificado';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        name[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 20,
                          color: Theme.of(context).colorScheme.onPrimary,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            specialty,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                    size: 18,
                                  ),
                                  Text(
                                    ' $rating',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    size: 18,
                                  ),
                                  Text(
                                    ' $distance km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                      foregroundColor: Theme.of(context).colorScheme.onTertiary,
                    ),
                    onPressed: () => _sendOffer(tech),
                    icon: const Icon(Icons.handshake),
                    label: const Text('Enviar oferta'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
