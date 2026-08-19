import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';

/// Registro de cliente (RF-LAND-002, RF-AUTH-001): nombre completo, documento
/// (CC único), teléfono y contraseña. Al registrarse, vuelve al login para
/// ingresar con el documento.
class RegisterClientScreen extends StatefulWidget {
  const RegisterClientScreen({super.key});

  @override
  State<RegisterClientScreen> createState() => _RegisterClientScreenState();
}

class _RegisterClientScreenState extends State<RegisterClientScreen> {
  final _fullNameController = TextEditingController();
  final _documentController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    final fullName = _fullNameController.text.trim();
    final document = _documentController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (fullName.isEmpty || document.isEmpty || phone.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completá todos los campos para registrarte.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiClient.registerClient(
        fullName: fullName,
        document: document,
        phone: phone,
        password: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro exitoso. Ya podés iniciar sesión.')),
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
        title: const Text('Registro de cliente'),
        backgroundColor: const Color(0xFF0A1632),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
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
                          key: const Key('register_client_full_name'),
                          controller: _fullNameController,
                          decoration: _inputDecoration(
                            'Nombre completo',
                            Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('register_client_document'),
                          controller: _documentController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(
                            'Documento (CC)',
                            Icons.badge_outlined,
                            hint: 'Ej. 1123456789',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('register_client_phone'),
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _inputDecoration(
                            'Teléfono',
                            Icons.phone_outlined,
                            hint: 'Ej. 3001234567',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('register_client_password'),
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
              ],
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