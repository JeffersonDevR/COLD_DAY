import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

// ─── Design tokens ─────────────────────────────────────────────────────────
const _bg = Color(0xFF080F1E);
const _accent = Color(0xFF5BC8F5);
const _textPrimary = Colors.white;
const _textMuted = Color(0xFF6B7FA3);
const _surface = Color(0xFF111928);
const _errorColor = Color(0xFFFF6B6B);

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

    setState(() { _loading = true; _error = null; });

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
        SnackBar(
          content: const Text(
            'Registro enviado. Un administrador verificará tu cuenta.',
          ),
          backgroundColor: _accent.withValues(alpha: 0.15),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
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
      return 'Ese documento ya está registrado. Intentá iniciar sesión.';
    }
    if (msg.contains('422')) {
      return 'La contraseña debe tener mín. 8 caracteres, mayúscula, minúscula y dígito.';
    }
    return 'No se pudo completar el registro. Verificá tu conexión.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: const Icon(Icons.arrow_back, color: _textMuted, size: 22),
              ),
              const SizedBox(height: 24),

              // ── Headline ───────────────────────────────────────────────
              const Text(
                'Registrate\ncomo técnico',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  height: 1.2,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tu cuenta quedará pendiente de verificación',
                style: TextStyle(fontSize: 14, color: _textMuted),
              ),
              const SizedBox(height: 28),

              // ── Form ───────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Field(
                        controller: _fullNameController,
                        label: 'Nombre completo',
                        testKey: 'register_tech_full_name',
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        controller: _documentController,
                        label: 'Documento (CC)',
                        testKey: 'register_tech_document',
                        keyboardType: TextInputType.number,
                        hint: 'Ej. 1098765432',
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        controller: _phoneController,
                        label: 'Teléfono',
                        testKey: 'register_tech_phone',
                        keyboardType: TextInputType.phone,
                        hint: 'Ej. 3012345678',
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        controller: _passwordController,
                        label: 'Contraseña',
                        testKey: 'register_tech_password',
                        obscure: _obscurePassword,
                        hint: 'Mín. 8 car., mayúscula, minúscula y dígito',
                        onToggleObscure: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        controller: _specialtyController,
                        label: 'Especialidad',
                        testKey: 'register_tech_specialty',
                        hint: 'Ej. Aires acondicionados',
                      ),
                      const SizedBox(height: 12),

                      // ── Coordinates ────────────────────────────────────
                      const Text(
                        'Ubicación (pre-cargada: Cúcuta)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _textMuted,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _Field(
                              controller: _latController,
                              label: 'Latitud',
                              testKey: 'register_tech_latitude',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Field(
                              controller: _lonController,
                              label: 'Longitud',
                              testKey: 'register_tech_longitude',
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                            ),
                          ),
                        ],
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 15, color: _errorColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    fontSize: 13, color: _errorColor),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),
                      _PrimaryButton(
                        label: 'Enviar solicitud',
                        loading: _loading,
                        onTap: _register,
                      ),
                      const SizedBox(height: 24),
                    ],
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

// ─── Shared field ─────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String testKey;
  final bool obscure;
  final String? hint;
  final TextInputType keyboardType;
  final VoidCallback? onToggleObscure;

  const _Field({
    required this.controller,
    required this.label,
    required this.testKey,
    this.obscure = false,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: Key(testKey),
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: _textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _textMuted, fontSize: 14),
        hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: _textMuted,
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
          backgroundColor: _accent,
          foregroundColor: const Color(0xFF080F1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: loading ? null : onTap,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF080F1E),
                ),
              )
            : Text(label),
      ),
    );
  }
}