import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

class TechnicianMapScreen extends StatefulWidget {
  final int requestId;
  final double latitude;
  final double longitude;

  const TechnicianMapScreen({
    super.key,
    required this.requestId,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<TechnicianMapScreen> createState() => _TechnicianMapScreenState();
}

class _TechnicianMapScreenState extends State<TechnicianMapScreen> {
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo de traslado (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: diagnosisController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              if (transport == null || transport < 0 || diagnosis == null || diagnosis < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Los costos deben ser >= 0')),
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
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
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
                Navigator.pop(context); // Close bottom sheet
              },
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar la oferta: $e')),
      );
    }
  }

  void _showTechnicianDetails(Map<String, dynamic> tech) {
    final rating = (tech['rating'] as num).toDouble();
    final distance = (tech['distance_km'] as num).toDouble();
    final name = tech['name'] as String;
    final specialty = tech['specialty'] as String? ?? 'Técnico certificado';
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.blueAccent,
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(specialty, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: 4),
                Text('$rating', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 24),
                const Icon(Icons.location_on, color: Colors.blueGrey, size: 20),
                const SizedBox(width: 4),
                Text('$distance km', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _sendOffer(tech),
                icon: const Icon(Icons.handshake),
                label: const Text('Enviar oferta', style: TextStyle(fontSize: 16)),
              ),
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
        title: Text('Mapa de Técnicos #${widget.requestId}'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(widget.latitude, widget.longitude),
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.coldday.app',
                    ),
                    MarkerLayer(
                      markers: [
                        // Client marker
                        Marker(
                          point: LatLng(widget.latitude, widget.longitude),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                        ),
                        // Technician markers
                        ..._technicians.map((tech) {
                          // Note: In a real app, API should return tech lat/lon. 
                          // Here we fallback to client location + small offset if missing for demo.
                          final lat = tech['latitude'] as double? ?? widget.latitude + 0.01;
                          final lon = tech['longitude'] as double? ?? widget.longitude + 0.01;
                          return Marker(
                            point: LatLng(lat, lon),
                            width: 60,
                            height: 60,
                            child: GestureDetector(
                              onTap: () => _showTechnicianDetails(tech),
                              child: const Column(
                                children: [
                                  Icon(Icons.engineering, color: Colors.green, size: 30),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
    );
  }
}
