import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:cold_day_flutter/core/map/map_config.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';
import 'package:cold_day_flutter/features/technician/bid_submission_screen.dart';

class TechnicianMapScreen extends StatefulWidget {
  const TechnicianMapScreen({super.key});

  @override
  State<TechnicianMapScreen> createState() => _TechnicianMapScreenState();
}

class _TechnicianMapScreenState extends State<TechnicianMapScreen> {
  final _mapController = MapController();
  List<Map<String, dynamic>> _requests = [];
  double _radius = 10;
  String? _serviceType;
  int? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await ApiClient.fetchTechnicianRadar(radiusKm: _radius);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _selectedId = null;
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = ApiClient.userFacingError(
            error,
            action: 'cargar el radar',
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _coordinate(Object? value, {required bool latitude}) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) return null;
    if (latitude ? number < -90 || number > 90 : number < -180 || number > 180)
      return null;
    return number;
  }

  List<Map<String, dynamic>> get _validRequests => _requests.where((request) {
    final lat = _coordinate(request['latitude'], latitude: true);
    final lon = _coordinate(request['longitude'], latitude: false);
    if (lat == null || lon == null) return false;
    if (_serviceType == null) return true;
    final type =
        request['service_type'] ??
        request['category'] ??
        request['category_name'];
    return type is String &&
        type.toLowerCase().contains(_serviceType!.toLowerCase());
  }).toList();

  void _select(Map<String, dynamic> request) {
    final id = request['id'] as int?;
    final lat = _coordinate(request['latitude'], latitude: true);
    final lon = _coordinate(request['longitude'], latitude: false);
    if (id == null || lat == null || lon == null) return;
    setState(() => _selectedId = id);
    _mapController.move(LatLng(lat, lon), 15);
  }

  Future<void> _showFilters() async {
    var radius = _radius;
    var type = _serviceType;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Filtros del radar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('Radio: ${radius.toStringAsFixed(0)} km'),
                Slider(
                  value: radius,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${radius.toStringAsFixed(0)} km',
                  onChanged: (value) => setSheetState(() => radius = value),
                ),
                DropdownButtonFormField<String?>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Tipo o categoría',
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem(
                      value: 'repair',
                      child: Text('Reparación'),
                    ),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Mantenimiento'),
                    ),
                    DropdownMenuItem(
                      value: 'installation',
                      child: Text('Instalación'),
                    ),
                  ],
                  onChanged: (value) => setSheetState(() => type = value),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Aplicar filtros',
                  icon: Icons.check,
                  onPressed: () {
                    setState(() {
                      _radius = radius;
                      _serviceType = type;
                    });
                    Navigator.pop(context);
                    _loadRequests();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _offer(Map<String, dynamic> request) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BidSubmissionScreen(
          requestId: request['id'] as int,
          equipment: request['equipment'] as String? ?? 'Solicitud',
        ),
      ),
    );
    if (submitted == true && mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oferta enviada')));
  }

  @override
  Widget build(BuildContext context) {
    final requests = _validRequests;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar de solicitudes'),
        actions: [
          IconButton(
            onPressed: _showFilters,
            icon: const Icon(Icons.tune),
            tooltip: 'Filtrar',
          ),
          IconButton(
            onPressed: _loading ? null : _loadRequests,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AsyncStateView(
              icon: Icons.cloud_off,
              message: _error!,
              action: _loadRequests,
            )
          : requests.isEmpty
          ? AsyncStateView(
              icon: _requests.isEmpty ? Icons.radar : Icons.location_off,
              message: _requests.isEmpty
                  ? 'No hay solicitudes cercanas'
                  : _serviceType == null
                  ? 'No hay solicitudes con ubicación válida'
                  : 'No hay resultados con estos filtros',
              action: _loadRequests,
            )
          : Column(
              children: [
                Expanded(flex: 5, child: _buildMap(requests)),
                if (_selectedId != null)
                  _RequestDetails(
                    request: requests.firstWhere(
                      (item) => item['id'] == _selectedId,
                    ),
                    onOffer: () => _offer(
                      requests.firstWhere((item) => item['id'] == _selectedId),
                    ),
                  ),
                Expanded(
                  flex: 4,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _RequestTile(
                      request: requests[index],
                      selected: requests[index]['id'] == _selectedId,
                      onTap: () => _select(requests[index]),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> requests) {
    final points = requests
        .map(
          (request) => LatLng(
            _coordinate(request['latitude'], latitude: true)!,
            _coordinate(request['longitude'], latitude: false)!,
          ),
        )
        .toList();
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 13,
        onMapReady: () {
          if (points.length > 1)
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(48),
                maxZoom: 16,
              ),
            );
        },
      ),
      children: [
        TileLayer(
          urlTemplate: mapTileUrl,
          userAgentPackageName: 'com.coldday.app',
        ),
        MarkerLayer(
          markers: requests.map((request) {
            final point = LatLng(
              _coordinate(request['latitude'], latitude: true)!,
              _coordinate(request['longitude'], latitude: false)!,
            );
            final selected = request['id'] == _selectedId;
            return Marker(
              point: point,
              width: 56,
              height: 56,
              child: Semantics(
                button: true,
                label: 'Solicitud ${request['id']}',
                child: GestureDetector(
                  onTap: () => _select(request),
                  child: Icon(
                    Icons.location_on,
                    size: selected ? 50 : 42,
                    color: selected
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution(mapAttribution)],
        ),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.selected,
    required this.onTap,
  });
  final Map<String, dynamic> request;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
    child: Semantics(
      button: true,
      selected: selected,
      label: 'Solicitud ${request['id']}',
      child: ListTile(
        onTap: onTap,
        minVerticalPadding: 12,
        leading: CircleAvatar(child: Text('${request['id']}')),
        title: Text(
          request['equipment'] as String? ?? 'Solicitud',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          request['description'] as String? ?? 'Sin descripción',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.center_focus_strong),
      ),
    ),
  );
}

class _RequestDetails extends StatelessWidget {
  const _RequestDetails({required this.request, required this.onOffer});
  final Map<String, dynamic> request;
  final VoidCallback onOffer;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 4,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['equipment'] as String? ?? 'Solicitud',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  request['description'] as String? ?? 'Sin descripción',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${request['service_type'] ?? request['category'] ?? 'Tipo no indicado'} · ${request['distance_km'] is num ? '${(request['distance_km'] as num).toStringAsFixed(1)} km' : 'Distancia no indicada'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Text('Ubicación disponible'),
              ],
            ),
          ),
          AppButton(
            label: 'Enviar oferta',
            icon: Icons.handshake,
            onPressed: onOffer,
          ),
        ],
      ),
    ),
  );
}
