import 'package:flutter/material.dart';
import 'package:cold_day_flutter/features/equipment/equipment_selection_screen.dart';
import 'package:cold_day_flutter/features/placeholder/coming_soon_screen.dart';

enum LoginMode { client, technician, provider }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.mode = LoginMode.client});

  final LoginMode mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  String get _title => switch (widget.mode) {
        LoginMode.client => 'Iniciar sesión',
        LoginMode.technician => 'Acceso de técnico',
        LoginMode.provider => 'Acceso de proveedor',
      };

  String get _tagline => switch (widget.mode) {
        LoginMode.client => 'Ingresá para pedir un técnico',
        LoginMode.technician => 'Ingresá para ofrecer tus servicios',
        LoginMode.provider => 'Ingresá para administrar tu negocio',
      };

  // Login de prueba para el MVP: cualquier credencial entra
  Future<void> _login() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600)); // simula espera

    if (!mounted) return;

    // Cliente -> flujo de pedido; técnico/proveedor -> placeholder por ahora
    final next = widget.mode == LoginMode.client
        ? const EquipmentSelectionScreen()
        : ComingSoonScreen(
            title: _title,
            message: widget.mode == LoginMode.technician
                ? 'El flujo de técnicos llega próximamente.'
                : 'El flujo de proveedores llega próximamente.',
          );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E), // azul oscuro
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Título según el rol
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _tagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF90CAF9)),
                ),
                const SizedBox(height: 28),

                // Logo de la app
                Container(
                  height: 220,
                  width: 220,
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.ac_unit,
                      size: 130,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration(
                    'Correo electrónico',
                    Icons.person_outline,
                    hint: 'ejemplo@correo.com',
                  ),
                ),
                const SizedBox(height: 16),

                // Contraseña
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration(
                    'Contraseña',
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Botón ingresar
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _loading ? null : _login,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: const Text(
                      'Ingresar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Registro disponible próximamente (MVP en pruebas)',
                        ),
                      ),
                    );
                  },
                  child: const Text('¿No tenés cuenta? Registrate'),
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
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}