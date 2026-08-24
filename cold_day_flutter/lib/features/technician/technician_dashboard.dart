import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/radar/technician_map_screen.dart';
import 'package:cold_day_flutter/features/request/request_status.dart';
import 'package:cold_day_flutter/features/technician/bid_submission_screen.dart';
import 'package:cold_day_flutter/features/technician/diagnosis_screen.dart';
import 'package:cold_day_flutter/features/technician/pact_proposal_screen.dart';
import 'package:cold_day_flutter/features/technician/service_config_screen.dart';

class TechnicianDashboard extends StatefulWidget {
  const TechnicianDashboard({super.key});

  @override
  State<TechnicianDashboard> createState() => _TechnicianDashboardState();
}

class _TechnicianDashboardState extends State<TechnicianDashboard> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic>? _active;
  bool _loading = true;
  String? _error;
  bool _publishingLocation = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await ApiClient.fetchTechnicianRadar();
      Map<String, dynamic>? active;
      try {
        active = await ApiClient.fetchTechnicianActiveService();
      } catch (_) {
        // Keep the radar usable when an older dev server lacks this additive endpoint.
      }
      if (mounted)
        setState(() {
          _requests = requests;
          _active = active;
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = ApiClient.userFacingError(
            error,
            action: 'cargar tu panel',
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _publishLocation() async {
    final requestId = _active?['id'] as int?;
    if (requestId == null) return;
    if (_publishingLocation) return;
    setState(() => _publishingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message(
          'Activá la ubicación del dispositivo para actualizar tu posición.',
        );
        return;
      }
      if (!mounted) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('Necesitás permitir la ubicación para informar tu avance.');
        return;
      }
      if (!mounted) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude < -90 ||
          position.latitude > 90 ||
          position.longitude < -180 ||
          position.longitude > 180) {
        _message('El dispositivo devolvió una ubicación inválida.');
        return;
      }
      await ApiClient.sendLocation(
        requestId: requestId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _message('Ubicación actualizada');
    } catch (error) {
      _message(
        ApiClient.userFacingError(error, action: 'actualizar tu ubicación'),
      );
    } finally {
      if (mounted) setState(() => _publishingLocation = false);
    }
  }

  Future<void> _offer(Map<String, dynamic> request) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BidSubmissionScreen(
          requestId: request['id'] as int,
          equipment: request['equipment'] as String? ?? 'Solicitud',
        ),
      ),
    );
    if (result == true) {
      _message('¡Oferta enviada!');
      _load();
    }
  }

  Future<void> _action(Map<String, dynamic> request, String status) async {
    final id = request['id'] as int;
    if (status == 'diagnosis')
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DiagnosisScreen(requestId: id)),
      );
    if (!mounted) return;
    if (status == 'pact_proposed')
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PactProposalScreen(requestId: id)),
      );
    if (!mounted) return;
    if (status == 'in_progress') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Finalizar servicio'),
          content: const Text('¿Finalizar el servicio?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finalizar'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await ApiClient.completeServiceRequest(requestId: id);
        if (!mounted) return;
        _message('Servicio completado');
      }
    }
    _load();
  }

  void _requestAction(Map<String, dynamic> request) {
    final status = request['status'] as String? ?? '';
    if (status == 'requested' || status == 'bidding') {
      _offer(request);
    } else {
      _action(request, status);
    }
  }

  Future<void> _logout() async {
    final token = await TokenStore.readRefreshToken();
    if (token != null) {
      try {
        await ApiClient.logout(token);
      } catch (_) {}
    }
    await TokenStore.clear();
    if (mounted)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Panel del técnico'),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ServiceConfigScreen()),
          ),
          icon: const Icon(Icons.settings),
          tooltip: 'Configurar servicios',
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TechnicianMapScreen()),
          ),
          icon: const Icon(Icons.map_outlined),
          tooltip: 'Abrir radar',
        ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar',
        ),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          tooltip: 'Cerrar sesión',
        ),
      ],
    ),
    body: _body(),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return AsyncStateView(
        icon: Icons.cloud_off,
        message: _error!,
        action: _load,
      );
    final newRequests = _requests;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tu jornada', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Encontrá oportunidades y seguí tus servicios activos.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Servicio activo',
            subtitle: 'Seguimiento de tu trabajo en curso',
          ),
          const SizedBox(height: 8),
          _active == null
              ? const AppCard(
                  child: Text('No tenés servicios activos en este momento.'),
                )
              : _RequestCard(
                  request: _active!,
                  onAction: () => _action(_active!, 'in_progress'),
                  onLocation: _publishLocation,
                  locationLoading: _publishingLocation,
                ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Nuevas solicitudes',
            subtitle: '${newRequests.length} oportunidades cercanas',
          ),
          const SizedBox(height: 8),
          if (newRequests.isEmpty)
            const AppCard(child: Text('No hay solicitudes cercanas'))
          else
            ...newRequests.map(
              (request) => _RequestCard(
                request: request,
                onAction: () => _requestAction(request),
              ),
            ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Resumen',
            subtitle: 'Actividad disponible en el radar',
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Row(
              children: [
                Icon(
                  Icons.near_me,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${newRequests.length} solicitudes en tu radio actual',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onAction,
    this.onLocation,
    this.locationLoading = false,
  });
  final Map<String, dynamic> request;
  final VoidCallback onAction;
  final VoidCallback? onLocation;
  final bool locationLoading;

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? '';
    final bidPending = request['my_bid_status'] == 'pending';
    final label = bidPending
        ? 'Oferta enviada'
        : status == 'in_progress'
        ? 'Finalizar servicio'
        : status == 'requested' || status == 'bidding'
        ? 'Enviar oferta'
        : status == 'diagnosis'
        ? 'Registrar diagnóstico'
        : status == 'pact_proposed'
        ? 'Proponer pacto'
        : requestStatusLabel(status);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: Text(
                  request['equipment'] as String? ?? 'Solicitud',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusBadge(
                label: bidPending
                    ? 'Oferta enviada'
                    : requestStatusLabel(status),
              ),
            ],
          ),
          if ((request['description'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request['description'] as String,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          if (onLocation != null) ...[
            if (!bidPending)
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: locationLoading
                      ? 'Publicando ubicación...'
                      : 'Actualizar ubicación',
                  icon: Icons.my_location,
                  onPressed: locationLoading ? null : onLocation,
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (!bidPending)
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: label,
                icon: Icons.arrow_forward,
                onPressed: onAction,
              ),
            ),
        ],
      ),
    );
  }
}
