import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/request/client_history_screen.dart';
import 'package:cold_day_flutter/core/theme/app_theme.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';

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
  String? _catalogError;
  bool _isLoading = false;
  bool _locating = false;
  bool _loadingSummary = true;
  String? _summaryError;
  int _activeServices = 0;

  double? currentLat;
  double? currentLon;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadSummary();
  }

  Future<void> _loadCatalog() async {
    try {
      final categories = await ApiClient.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loadingCatalog = false;
        _catalogError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _catalogError = 'No se pudo cargar el catálogo.';
      });
    }
  }

  Future<void> _loadSummary() async {
    try {
      final requests = await ApiClient.fetchMyRequests();
      const activeStates = {
        'requested',
        'bidding',
        'diagnosis',
        'pact_proposed',
        'in_progress',
      };
      if (!mounted) return;
      setState(() {
        _activeServices = requests
            .where((request) => activeStates.contains(request['status']))
            .length;
        _loadingSummary = false;
        _summaryError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSummary = false;
        _summaryError = 'No se pudo cargar el resumen.';
      });
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
    if (currentLat == null || currentLon == null) {
      _showMessage('Indica tu ubicación actual antes de crear la solicitud.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final budget = double.tryParse(_budgetController.text);
      await ApiClient.createServiceRequest(
        serviceType: _serviceType,
        description: _descriptionController.text,
        latitude: currentLat!,
        longitude: currentLon!,
        budgetOffered: budget,
        categoryHint: _categoryHint,
      );

      if (!mounted) return;

      await _showConfirmation();
    } catch (e) {
      _showMessage('Error al crear la solicitud: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showConfirmation() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Solicitud creada'),
        content: const Text(
          'Tu solicitud quedó registrada. Podrás revisar ofertas y avances desde Mis servicios.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Seguir aquí'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClientHistoryScreen()),
              );
            },
            child: const Text('Ver Mis servicios'),
          ),
        ],
      ),
    );
    if (mounted) _loadSummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Qué necesitás?'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.ac_unit,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'COLD DAY',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Recuperá tu confort',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Contanos qué necesitás y conectamos tu solicitud con técnicos cercanos.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    child: const Icon(Icons.home_work_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Solicita un servicio',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _loadingSummary
                              ? 'Cargando tus servicios...'
                              : _summaryError ??
                                    '$_activeServices servicio(s) activo(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mis servicios',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClientHistoryScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
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
            else if (_catalogError != null)
              AppCard(child: Text(_catalogError!))
            else
              InputDecorator(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
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
                        final name = cat['name']?.toString() ?? 'Equipo';
                        return DropdownMenuItem(value: name, child: Text(name));
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
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.location_on,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Ubicación del servicio'),
                      subtitle: Text(
                        currentLat == null
                            ? 'Aún no definida. Necesitamos tu ubicación para enviar la solicitud.'
                            : 'Ubicación actual obtenida por GPS',
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _locating ? null : _useGpsLocation,
                        icon: _locating
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
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
            if (currentLat == null) ...[
              const SizedBox(height: 8),
              Text(
                'Toca “Usar mi ubicación actual” para solicitar permiso o reintentar. Si el permiso fue bloqueado, habilítalo en la configuración del dispositivo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isLoading ? null : _submitRequest,
                icon: _isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.onPrimary,
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
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }
}
