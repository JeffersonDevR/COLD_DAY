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
      final technicians = await ApiClient.findNearbyTechnicians(
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      setState(() => _technicians = technicians);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudieron cargar los técnicos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _coordinate(Object? value, {required bool latitude}) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) return null;
    if (latitude
        ? number < -90 || number > 90
        : number < -180 || number > 180) {
      return null;
    }
    return number;
  }

  void _showTechnicianDetails(Map<String, dynamic> tech) {
    final rating = (tech['rating'] as num?)?.toDouble() ?? 5.0;
    final name = tech['name'] as String? ?? 'Técnico';
    final specialty = tech['specialty'] as String? ?? 'Técnico';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                  child: Icon(
                    Icons.handyman,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        specialty,
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '$rating',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Radar de Técnicos #${widget.requestId}'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
              : _technicians.isEmpty
          ? const Center(child: Text('No se encontraron técnicos en tu área'))
          : _technicians.every(
                  (tech) =>
                      _coordinate(tech['latitude'], latitude: true) != null &&
                      _coordinate(tech['longitude'], latitude: false) != null,
                )
          ? FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(widget.latitude, widget.longitude),
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.coldday.app',
                ),
                MarkerLayer(
                  markers: [
                    // Client Marker (Icono de Casa/Usuario)
                    Marker(
                      point: LatLng(widget.latitude, widget.longitude),
                      width: 45,
                      height: 45,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue, width: 2),
                        ),
                        child: const Icon(
                          Icons.home,
                          color: Colors.blue,
                          size: 24,
                        ),
                      ),
                    ),
                    // Technician Markers (Iconos de llave/herramienta verdes)
                    ..._technicians.map((tech) {
                      final lat = _coordinate(
                        tech['latitude'],
                        latitude: true,
                      )!;
                      final lon = _coordinate(
                        tech['longitude'],
                        latitude: false,
                      )!;
                      return Marker(
                        point: LatLng(lat, lon),
                        width: 50,
                        height: 50,
                        child: GestureDetector(
                          onTap: () => _showTechnicianDetails(tech),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green, width: 2),
                            ),
                            child: const Icon(
                              Icons.handyman,
                              color: Colors.green,
                              size: 24,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_off, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No hay técnicos con ubicación válida',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'La ubicación se mostrará cuando esté disponible.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
