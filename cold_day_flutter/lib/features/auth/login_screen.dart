import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/auth/auth_router.dart';
import 'package:cold_day_flutter/features/auth/register_client_screen.dart';
import 'package:cold_day_flutter/features/auth/register_technician_screen.dart';
import 'package:cold_day_flutter/core/theme/app_theme.dart';

enum LoginMode { client, technician, admin }

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

  String get _roleLabel => switch (widget.mode) {
    LoginMode.client => 'cliente',
    LoginMode.technician => 'técnico',
    LoginMode.admin => 'administrador',
  };

  String get _headline => switch (widget.mode) {
    LoginMode.client => 'Bienvenido',
    LoginMode.technician => 'Acceso técnico',
    LoginMode.admin => 'Panel admin',
  };

  Future<void> _login() async {
    final document = _documentController.text.trim();
    final password = _passwordController.text;
    if (document.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completá documento y contraseña.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiClient.login(
        document: document,
        password: password,
      );
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
      setState(() => _error = 'Documento o contraseña incorrectos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToRegister() {
    final next = widget.mode == LoginMode.technician
        ? const RegisterTechnicianScreen()
        : const RegisterClientScreen();
    Navigator.push(context, MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back ───────────────────────────────────────────────────
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),

              const Spacer(flex: 2),

              // ── Headline ───────────────────────────────────────────────
              Icon(
                Icons.ac_unit,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: 16),
              Text(
                _headline,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 32,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ingresá como $_roleLabel',
                style: Theme.of(context).textTheme.bodyLarge,
              ),

              const SizedBox(height: 40),

              // ── Fields ─────────────────────────────────────────────────
              _Field(
                controller: _documentController,
                label: 'Documento (CC)',
                keyboardType: TextInputType.number,
                testKey: 'login_document',
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _passwordController,
                label: 'Contraseña',
                obscure: _obscurePassword,
                testKey: 'login_password',
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                onSubmitted: (_) => _loading ? null : _login(),
              ),

              // ── Error ──────────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // ── CTA ────────────────────────────────────────────────────
              _PrimaryButton(
                label: 'Ingresar',
                loading: _loading,
                onTap: _login,
              ),

              if (widget.mode != LoginMode.admin) ...[
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: _loading ? null : _goToRegister,
                    child: Text(
                      '¿Sin cuenta? Registrate',
                      style: TextStyle(
                        fontSize: 14,
                        color: _loading
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared input field ──────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final String testKey;
  final TextInputType keyboardType;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.testKey,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.onToggleObscure,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: Key(testKey),
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: onToggleObscure,
              )
            : null,
      ),
    );
  }
}

// ─── Primary button ───────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.onSecondary,
        ),
        onPressed: loading ? null : onTap,
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              )
            : Text(label),
      ),
    );
  }
}
