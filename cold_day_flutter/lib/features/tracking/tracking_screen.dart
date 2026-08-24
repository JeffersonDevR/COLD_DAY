import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/map/map_config.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';

class TrackingScreen extends StatefulWidget {
  final int requestId;
  final double clientLat;
  final double clientLon;
  final String? clientName;
  final String? technicianName;

  const TrackingScreen({
    super.key,
    required this.requestId,
    required this.clientLat,
    required this.clientLon,
    this.clientName,
    this.technicianName,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Timer? _timer;
  Map<String, dynamic>? _techLocation;
  bool _loading = true;
  String? _error;
  final MapController _mapController = MapController();
  LatLng? _lastTechnicianPoint;

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
      final latitude = _coordinate(loc?['latitude'], latitude: true);
      final longitude = _coordinate(loc?['longitude'], latitude: false);
      final hasCoordinateValue =
          loc?['latitude'] != null || loc?['longitude'] != null;
      if (loc != null &&
          hasCoordinateValue &&
          (latitude == null || longitude == null)) {
        setState(() {
          _techLocation = null;
          _loading = false;
          _error = 'La ubicación recibida no tiene coordenadas válidas.';
        });
        return;
      }
      final point = latitude == null || longitude == null
          ? null
          : LatLng(latitude, longitude);
      setState(() {
        _techLocation = point == null ? null : loc;
        _loading = false;
        _error = null;
        _lastTechnicianPoint = point;
      });
      if (point != null) {
        try {
          _mapController.move(point, _mapController.camera.zoom);
        } on StateError {
          // The first response can arrive before FlutterMap attaches its controller.
        }
      }
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
        body: AsyncStateView(
          icon: Icons.location_disabled,
          message: 'La ubicación del servicio no es válida.',
          action: () {},
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rastreo del Técnico')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _contextHeader(context),
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    leading: const Icon(Icons.warning_amber),
                    actions: [
                      TextButton(
                        onPressed: _fetchLocation,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                if (_techLocation == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('El técnico todavía no publicó su ubicación.'),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(
                            clientLatitude,
                            clientLongitude,
                          ),
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
                                child: Icon(
                                  Icons.home,
                                  color: Theme.of(context).colorScheme.primary,
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
                                  child: Icon(
                                    Icons.engineering,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                    size: 40,
                                  ),
                                ),
                            ],
                          ),
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(mapAttribution),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 16,
                        bottom: 48,
                        child: Semantics(
                          button: true,
                          label:
                              'Centrar el mapa en la última ubicación válida',
                          child: FloatingActionButton.small(
                            heroTag: 'tracking-recenter',
                            onPressed: _recenter,
                            tooltip: 'Centrar ubicación',
                            child: const Icon(Icons.my_location),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _contextHeader(BuildContext context) {
    final updatedAt = DateTime.tryParse(
      '${_techLocation?['updated_at'] ?? ''}',
    );
    final age = updatedAt == null ? null : DateTime.now().difference(updatedAt);
    final stale = age != null && age > const Duration(minutes: 2);
    final freshness = updatedAt == null
        ? 'Sin actualización todavía'
        : stale
        ? 'Ubicación desactualizada (${_formatAge(age)})'
        : 'Actualizada hace ${_formatAge(age)}';
    return AppCard(
      child: Row(
        children: [
          Icon(
            Icons.location_on,
            color: stale
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.technicianName ?? 'Técnico asignado',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Servicio para ${widget.clientName ?? 'cliente'}'),
                Text(freshness, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  'Solo ubicación en vivo. No incluye ETA ni ruta.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAge(Duration? age) {
    if (age == null) return 'sin fecha';
    if (age.inMinutes > 0) return '${age.inMinutes} min';
    return '${age.inSeconds.clamp(0, 59)} s';
  }

  void _recenter() {
    final point = _lastTechnicianPoint;
    if (point != null) _mapController.move(point, 15);
  }
}
