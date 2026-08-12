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
      final technicians = await ApiClient.findNearbyTechnicians(
        latitude: widget.latitude,
        longitude: widget.longitude,
        radiusKm: 5.0,
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

  Future<void> _acceptTechnician(Map<String, dynamic> tech) async {
    // El precio se define en la contraoferta del técnico.
    // Para el MVP, el cliente acepta con el presupuesto que ofreció o un valor sugerido.
    final controller = TextEditingController(text: '80000');

    final price = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar oferta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Aceptar a ${tech['name']}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Precio ofrecido (COP)',
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
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (price == null || !mounted) return;

    try {
      await ApiClient.sendTechnicianBid(
        serviceRequestId: widget.requestId,
        technicianId: tech['id'],
        priceOffered: price,
        estimatedTimeMinutes: 45,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('¡Servicio Asignado! ❄️'),
          content: Text(
            'Has seleccionado a ${tech['name']} por \$${price.toStringAsFixed(0)}. '
            'El técnico fue notificado y va en camino.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al aceptar oferta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Radar de Técnicos #${widget.requestId}'),
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
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.radar, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Técnicos certificados en climatización a menos de 5 km',
                      style: TextStyle(
                        color: Colors.white,
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
            Text('Buscando técnicos cercanos...'),
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
              const Text(
                'No se pudo conectar con el radar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.radar, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No hay técnicos en el radio',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Probá ampliando el radio de búsqueda',
              style: TextStyle(color: Colors.grey),
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
                      backgroundColor: Colors.blueAccent,
                      child: Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
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
                            style: const TextStyle(
                              color: Colors.grey,
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
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 18),
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
                                  const Icon(Icons.location_on,
                                      color: Colors.blueGrey, size: 18),
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
                      backgroundColor: Colors.green.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _acceptTechnician(tech),
                    icon: const Icon(Icons.handshake),
                    label: const Text('Aceptar oferta'),
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
