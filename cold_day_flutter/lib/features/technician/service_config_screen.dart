import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

class ServiceConfigScreen extends StatefulWidget {
  const ServiceConfigScreen({super.key});

  @override
  State<ServiceConfigScreen> createState() => _ServiceConfigScreenState();
}

class _ServiceConfigScreenState extends State<ServiceConfigScreen> {
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _myServices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await ApiClient.fetchCatalog();
      final myServices = await ApiClient.fetchMyServices();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _myServices = myServices;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error al cargar datos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addService(int categoryId, List<String> types, String sector) async {
    try {
      await ApiClient.addMyService(categoryId: categoryId, serviceTypes: types, sector: sector);
      _showMessage('Servicio agregado');
      _loadData();
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Future<void> _removeService(int serviceId) async {
    try {
      await ApiClient.removeMyService(serviceId);
      _showMessage('Servicio eliminado');
      _loadData();
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis servicios'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _catalog.length,
                  itemBuilder: (context, index) {
                    final cat = _catalog[index];
                    final catId = cat['id'] as int;
                    
                    // Check if already configured
                    final existing = _myServices.where((s) => s['category_id'] == catId).toList();
                    final isEnabled = existing.isNotEmpty;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  cat['name'] as String,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Switch(
                                  value: isEnabled,
                                  onChanged: (val) {
                                    if (val) {
                                      // Default add
                                      _addService(catId, ['repair'], 'residential');
                                    } else {
                                      for (var s in existing) {
                                        _removeService(s['id'] as int);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (isEnabled) ...[
                              const SizedBox(height: 8),
                              const Text('Configurado como:', style: TextStyle(color: Colors.grey)),
                              ...existing.map((s) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Sector: ${s['sector']}'),
                                subtitle: Text('Tipos: ${(s['service_types'] as List).join(', ')}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeService(s['id'] as int),
                                ),
                              )),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
