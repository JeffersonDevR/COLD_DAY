import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/auth/auth_router.dart';
import 'package:cold_day_flutter/features/auth/register_client_screen.dart';
import 'package:cold_day_flutter/features/auth/register_technician_screen.dart';

enum LoginMode { client, technician }

/// Login real por documento (CC) + contraseña (RF-LAND-004, RF-AUTH-003):
/// cualquier credencial ya NO entra; el error 401 se muestra y la app no
/// navega. Al autenticar, guarda el par de tokens y rutea por rol (HU-AUTH-003).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.mode = LoginMode.client});

  final LoginMode mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _documentController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  String get _title => switch (widget.mode) {
        LoginMode.client => 'Iniciar sesión',
        LoginMode.technician => 'Acceso de técnico',
      };

  String get _tagline => switch (widget.mode) {
        LoginMode.client => 'Ingresá para pedir un técnico',
        LoginMode.technician => 'Ingresá para ofrecer tus servicios',
      };

  Future<void> _login() async {
    final document = _documentController.text.trim();
    final password = _passwordController.text;
    if (document.isEmpty || password.isEmpty) {
      setState(() => _error = 'Ingresá tu documento y tu contraseña.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiClient.login(document: document, password: password);
      final role = result['role'] as String? ?? 'client';
      final userId = result['user_id'] as int? ?? 0;

      await TokenStore.save(
        accessToken: result['access_token'] as String,
        refreshToken: result['refresh_token'] as String,
        role: role,
        userId: userId,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => roleHome(role)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Credenciales inválidas. Verificá tu documento y contraseña.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToRegister() {
    final next = widget.mode == LoginMode.technician
        ? const RegisterTechnicianScreen()
        : const RegisterClientScreen();
    Navigator.push(context, MaterialPageRoute(builder: (context) => next));
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
                  height: 180,
                  width: 180,
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.ac_unit,
                      size: 110,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Documento (CC)
                TextField(
                  key: const Key('login_document'),
                  controller: _documentController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    'Documento (CC)',
                    Icons.badge_outlined,
                    hint: 'Ej. 1123456789',
                  ),
                ),
                const SizedBox(height: 16),

                // Contraseña
                TextField(
                  key: const Key('login_password'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _loading ? null : _login(),
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
                const SizedBox(height: 20),

                // Error de autenticación (no se entra con cualquier credencial)
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFB71C1C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

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
                  onPressed: _loading ? null : _goToRegister,
                  child: Text(
                    widget.mode == LoginMode.technician
                        ? '¿No tenés cuenta? Registrate como técnico'
                        : '¿No tenés cuenta? Registrate',
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
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}