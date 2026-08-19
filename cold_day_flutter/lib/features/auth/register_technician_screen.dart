import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';

/// Registro de técnico (RF-LAND-003, RF-AUTH-002): datos personales +
/// especialidad + ubicación. El técnico queda `pending` hasta que el admin lo
/// verifique (HU-TEC-001). Coordenadas por defecto: Cúcuta (Nodo Tecnoparque).
class RegisterTechnicianScreen extends StatefulWidget {
  const RegisterTechnicianScreen({super.key});

  @override
  State<RegisterTechnicianScreen> createState() =>
      _RegisterTechnicianScreenState();
}

class _RegisterTechnicianScreenState extends State<RegisterTechnicianScreen> {
  final _fullNameController = TextEditingController();
  final _documentController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _latController = TextEditingController(text: '7.8939');
  final _lonController = TextEditingController(text: '-72.5078');
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    final fullName = _fullNameController.text.trim();
    final document = _documentController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final specialty = _specialtyController.text.trim();
    final latitude = double.tryParse(_latController.text.trim());
    final longitude = double.tryParse(_lonController.text.trim());

    if (fullName.isEmpty ||
        document.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        specialty.isEmpty) {
      setState(() => _error = 'Completá todos los campos para registrarte.');
      return;
    }
    if (latitude == null || longitude == null) {
      setState(() => _error = 'Ingresá coordenadas de ubicación válidas.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiClient.registerTechnician(
        fullName: fullName,
        document: document,
        phone: phone,
        password: password,
        specialty: specialty,
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registro exitoso. Tu cuenta será verificada por un administrador.',
          ),
        ),
      );
      Navigator.pop(context); // volver al login
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('409')) {
      return 'No se pudo completar el registro. Verificá los datos e intentá de nuevo.';
    }
    if (msg.contains('422')) {
      return 'La contraseña debe tener al menos 8 caracteres con mayúscula, '
          'minúscula y dígito.';
    }
    return 'No se pudo completar el registro. Verificá tu conexión e intentá de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E),
      appBar: AppBar(
        title: const Text('Registro de técnico'),
        backgroundColor: const Color(0xFF0A1632),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('register_tech_full_name'),
                      controller: _fullNameController,
                      decoration: _inputDecoration(
                        'Nombre completo',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('register_tech_document'),
                      controller: _documentController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(
                        'Documento (CC)',
                        Icons.badge_outlined,
                        hint: 'Ej. 1098765432',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('register_tech_phone'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        'Teléfono',
                        Icons.phone_outlined,
                        hint: 'Ej. 3012345678',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('register_tech_password'),
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: _inputDecoration(
                        'Contraseña',
                        Icons.lock_outline,
                        hint: 'Mín. 8 caracteres, mayúscula, minúscula y dígito',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('register_tech_specialty'),
                      controller: _specialtyController,
                      decoration: _inputDecoration(
                        'Especialidad',
                        Icons.handyman_outlined,
                        hint: 'Ej. Aires acondicionados',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('register_tech_latitude'),
                            controller: _latController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: _inputDecoration(
                              'Latitud',
                              Icons.explore_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const Key('register_tech_longitude'),
                            controller: _lonController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: _inputDecoration(
                              'Longitud',
                              Icons.explore_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB71C1C)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _loading ? null : _register,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_alt),
                        label: const Text(
                          'Registrarme',
                          style: TextStyle(
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
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF3F6FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}