import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/request/client_history_screen.dart';

class SimpleRequestScreen extends StatefulWidget {
  const SimpleRequestScreen({super.key});

  @override
  State<SimpleRequestScreen> createState() => _SimpleRequestScreenState();
}

class _SimpleRequestScreenState extends State<SimpleRequestScreen> {
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();

  String _serviceType = 'repair'; // 'repair', 'maintenance', 'installation'
  String? _categoryHint; // Can be null for "No estoy seguro"

  List<Map<String, dynamic>> _categories = [];
  bool _loadingCatalog = true;
  bool _isLoading = false;
  bool _locating = false;

  double currentLat = 7.8939;
  double currentLon = -72.5078;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final categories = await ApiClient.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loadingCatalog = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCatalog = false);
    }
  }

  Future<void> _useGpsLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage(
          'El GPS está desactivado. Activá la ubicación del dispositivo.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showMessage('Permiso de ubicación denegado.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Permiso de ubicación denegado permanentemente.');
        return;
      }
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
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submitRequest() async {
    if (_descriptionController.text.isEmpty) {
      _showMessage('Por favor describe el problema');
      return;
    }
    if (_descriptionController.text.length > 500) {
      _showMessage('La descripción no puede exceder los 500 caracteres');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final budget = double.tryParse(_budgetController.text);
      await ApiClient.createServiceRequest(
        serviceType: _serviceType,
        description: _descriptionController.text,
        latitude: currentLat,
        longitude: currentLon,
        budgetOffered: budget,
        categoryHint: _categoryHint,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ClientHistoryScreen()),
      );
    } catch (e) {
      _showMessage('Error al crear la solicitud: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Qué necesitás?'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Mi historial',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClientHistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final refresh = await TokenStore.readRefreshToken();
              if (refresh != null) {
                try {
                  await ApiClient.logout(refresh);
                } catch (_) {}
              }
              await TokenStore.clear();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF080F1E)
            : const Color(0xFFF8FAFC),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Describe el problema',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Ej. El aire acondicionado no enfría...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Tipo de servicio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'repair', label: Text('Reparación')),
                  ButtonSegment(
                    value: 'maintenance',
                    label: Text('Mantenimiento'),
                  ),
                  ButtonSegment(
                    value: 'installation',
                    label: Text('Instalación'),
                  ),
                ],
                selected: {_serviceType},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _serviceType = newSelection.first);
                },
              ),
              const SizedBox(height: 20),
              Text(
                '¿Qué tipo de equipo?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingCatalog)
                const Center(child: CircularProgressIndicator())
              else
                InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _categoryHint,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No estoy seguro'),
                        ),
                        ..._categories.map((cat) {
                          final name = cat['name'] as String;
                          return DropdownMenuItem(
                            value: name,
                            child: Text(name),
                          );
                        }),
                      ],
                      onChanged: (val) => setState(() => _categoryHint = val),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Presupuesto propuesto (opcional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
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
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
              ),
              const SizedBox(height: 20),
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
                          'Lat: ${currentLat.toStringAsFixed(5)}, '
                          'Lon: ${currentLon.toStringAsFixed(5)}',
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
                          onPressed: _locating ? null : _useGpsLocation,
                          icon: _locating
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
                            _locating
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
                  onPressed: _isLoading ? null : _submitRequest,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _isLoading ? 'Buscando...' : 'Buscar técnicos',
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
      ),
    );
  }
}
