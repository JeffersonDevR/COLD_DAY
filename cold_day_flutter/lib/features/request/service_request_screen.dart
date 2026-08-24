import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/client_history_screen.dart';

class ServiceRequestScreen extends StatefulWidget {
  final int equipmentId;
  final String sector;
  final String equipmentType;
  final String serviceType;

  const ServiceRequestScreen({
    super.key,
    required this.equipmentId,
    required this.sector,
    required this.equipmentType,
    required this.serviceType,
  });

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  bool isLoading = false;
  bool locating = false;

  // Coordenadas por defecto: Cúcuta, Colombia (Nodo Tecnoparque)
  // Se reemplazan con el GPS real cuando el usuario toca "Usar mi ubicación".
  double? currentLat;
  double? currentLon;

  Future<void> _useGpsLocation() async {
    setState(() => locating = true);

    try {
      // 1. Verificar que el GPS esté activado
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage(
          'El GPS está desactivado. Activá la ubicación del dispositivo.',
        );
        return;
      }

      // 2. Pedir permiso si hace falta
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showMessage(
          'Permiso de ubicación denegado. No podemos usar tu posición.',
        );
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Permiso de ubicación denegado permanentemente. Activálo desde la configuración del dispositivo.',
        );
        return;
      }

      // 3. Obtener la posición actual
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        currentLat = position.latitude;
        currentLon = position.longitude;
      });
      _showMessage('Ubicación actualizada con tu GPS ✅');
    } catch (e) {
      _showMessage('No se pudo obtener la ubicación: $e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submitRequest() async {
    if (_descriptionController.text.isEmpty) {
      _showMessage('Por favor describe el problema o servicio');
      return;
    }
    if (currentLat == null || currentLon == null) {
      _showMessage('Indica tu ubicación actual antes de crear la solicitud.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final budget = double.tryParse(_budgetController.text);

      // RF-SR-001: el dueño sale del token autenticado, no de un userId hardcoded.
      await ApiClient.createServiceRequest(
        equipmentId: widget.equipmentId,
        serviceType: widget.serviceType,
        description: _descriptionController.text,
        latitude: currentLat!,
        longitude: currentLon!,
        budgetOffered: budget,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Solicitud creada'),
          content: const Text(
            'Revisa las ofertas y avances desde Mis servicios.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ClientHistoryScreen(),
                  ),
                );
              },
              child: const Text('Ver Mis servicios'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serviceLabel = switch (widget.serviceType) {
      'installation' => 'Instalación',
      'maintenance' => 'Mantenimiento',
      'repair' => 'Reparación / Correctivo',
      _ => widget.serviceType,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles de la Solicitud'),
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.blueAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chips en Wrap para que nunca se desborden en pantallas chicas
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            widget.sector == 'residential'
                                ? 'Residencial'
                                : 'Industrial',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.blue.shade50,
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(
                            serviceLabel,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.green.shade50,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.ac_unit, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.equipmentType,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Describe el problema',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ej. El aire acondicionado no enfría y bota agua...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Presupuesto propuesto (opcional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Ej. 80000 (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Ubicación: botón para tomar el GPS real + vista de coordenadas
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.location_on,
                        color: Colors.redAccent,
                      ),
                      title: const Text('Ubicación del servicio'),
                      subtitle: Text(
                        currentLat == null
                            ? 'Aún no definida. Obtén tu ubicación por GPS.'
                            : 'Ubicación actual obtenida por GPS',
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueAccent,
                          side: const BorderSide(color: Colors.blueAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: locating ? null : _useGpsLocation,
                        icon: locating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blueAccent,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(
                          locating
                              ? 'Obteniendo ubicación...'
                              : 'Usar mi ubicación actual',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: isLoading ? null : _submitRequest,
                icon: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.radar),
                label: Text(
                  isLoading ? 'Lanzando solicitud...' : 'Lanzar al Radar',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
