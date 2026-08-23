import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/map/map_config.dart';

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
  String? _error;

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

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchLocation(),
    );
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
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo actualizar la ubicación.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientLatitude = _coordinate(widget.clientLat, latitude: true);
    final clientLongitude = _coordinate(widget.clientLon, latitude: false);
    if (clientLatitude == null || clientLongitude == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rastreo del Técnico')),
        body: const Center(
          child: Text('La ubicación del servicio no es válida.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rastreo del Técnico')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null && _techLocation == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
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
                            'Última actualización: ${_techLocation!['updated_at'] ?? 'sin fecha'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(clientLatitude, clientLongitude),
                      initialZoom: 14.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: mapTileUrl,
                        userAgentPackageName: 'com.coldday.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(clientLatitude, clientLongitude),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.home,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                          if (_coordinate(
                                    _techLocation?['latitude'],
                                    latitude: true,
                                  ) !=
                                  null &&
                              _coordinate(
                                    _techLocation?['longitude'],
                                    latitude: false,
                                  ) !=
                                  null)
                            Marker(
                              point: LatLng(
                                _coordinate(
                                  _techLocation!['latitude'],
                                  latitude: true,
                                )!,
                                _coordinate(
                                  _techLocation!['longitude'],
                                  latitude: false,
                                )!,
                              ),
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.engineering,
                                color: Colors.green,
                                size: 40,
                              ),
                            ),
                        ],
                      ),
                      RichAttributionWidget(
                        attributions: [TextSourceAttribution(mapAttribution)],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
