import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';

/// Technician radar map. Requests are supplied by the authenticated backend
/// endpoint, so markers always represent real nearby client requests.
class TechnicianMapScreen extends StatefulWidget {
  const TechnicianMapScreen({super.key});

  @override
  State<TechnicianMapScreen> createState() => _TechnicianMapScreenState();
}

class _TechnicianMapScreenState extends State<TechnicianMapScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await ApiClient.fetchTechnicianRadar();
      if (!mounted) return;
      setState(() => _requests = requests);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el mapa: $error');
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

  @override
  Widget build(BuildContext context) {
    final valid = _requests.where((request) {
      return _coordinate(request['latitude'], latitude: true) != null &&
          _coordinate(request['longitude'], latitude: false) != null;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar de solicitudes'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadRequests,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar radar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateMessage(
              icon: Icons.cloud_off,
              message: _error!,
              action: _loadRequests,
            )
          : valid.isEmpty
          ? _StateMessage(
              icon: _requests.isEmpty ? Icons.radar : Icons.location_off,
              message: _requests.isEmpty
                  ? 'No hay solicitudes cercanas'
                  : 'No hay solicitudes con ubicación válida',
              action: _loadRequests,
            )
          : Column(
              children: [
                Expanded(child: _buildMap(valid)),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: valid.length,
                    itemBuilder: (_, index) =>
                        _RequestTile(request: valid[index]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> requests) {
    final first = requests.first;
    final center = LatLng(
      _coordinate(first['latitude'], latitude: true)!,
      _coordinate(first['longitude'], latitude: false)!,
    );
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.coldday.app',
        ),
        MarkerLayer(
          markers: requests.map((request) {
            final point = LatLng(
              _coordinate(request['latitude'], latitude: true)!,
              _coordinate(request['longitude'], latitude: false)!,
            );
            return Marker(
              point: point,
              width: 48,
              height: 48,
              child: Tooltip(
                message: 'Solicitud #${request['id']}',
                child: Icon(
                  Icons.location_on,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${request['id']}')),
        title: Text(
          request['equipment'] as String? ?? 'Solicitud',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          request['description'] as String? ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.place),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String message;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: action,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}
