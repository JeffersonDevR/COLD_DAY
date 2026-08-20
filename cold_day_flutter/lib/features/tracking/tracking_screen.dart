import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

class TrackingScreen extends StatefulWidget {
  final int requestId;
  final double clientLat;
  final double clientLon;

  const TrackingScreen({
    super.key,
    required this.requestId,
    required this.clientLat,
    required this.clientLon,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Timer? _timer;
  Map<String, dynamic>? _techLocation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchLocation());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      final loc = await ApiClient.fetchTechnicianLocation(widget.requestId);
      if (!mounted) return;
      setState(() {
        _techLocation = loc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastreo del Técnico'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_techLocation != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.green.shade50,
                    child: Row(
                      children: [
                        const Icon(Icons.delivery_dining, color: Colors.green),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'ETA: ${_techLocation!['eta'] ?? 'Calculando...'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(widget.clientLat, widget.clientLon),
                      initialZoom: 14.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.coldday.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(widget.clientLat, widget.clientLon),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.home, color: Colors.blue, size: 40),
                          ),
                          if (_techLocation != null && _techLocation!['latitude'] != null)
                            Marker(
                              point: LatLng(
                                (_techLocation!['latitude'] as num).toDouble(),
                                (_techLocation!['longitude'] as num).toDouble(),
                              ),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.engineering, color: Colors.green, size: 40),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
