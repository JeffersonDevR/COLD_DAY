import 'package:flutter/material.dart';
import 'package:cold_day_flutter/features/auth/login_screen.dart';
import 'package:cold_day_flutter/features/auth/register_client_screen.dart';
import 'package:cold_day_flutter/features/auth/register_technician_screen.dart';
import 'package:cold_day_flutter/features/pqr/pqr_screen.dart';

// ─── Design tokens ─────────────────────────────────────────────────────────
const _bg = Color(0xFF080F1E);
const _accent = Color(0xFF5BC8F5);
const _textPrimary = Colors.white;
const _textMuted = Color(0xFF6B7FA3);
const _surface = Color(0xFF111928);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
              const SizedBox(height: 48),

              // ── Brand ──────────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.ac_unit, color: _accent, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'Cold Day',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Técnicos certificados,\na un toque de distancia.',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  height: 1.2,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Refrigeración · A/C · Electricidad · Electrodomésticos',
                style: TextStyle(
                  fontSize: 13,
                  color: _textMuted,
                  letterSpacing: 0.1,
                ),
              ),

              const SizedBox(height: 48),

              // ── Primary actions ────────────────────────────────────────
              _RoleCard(
                icon: Icons.build_rounded,
                label: 'Necesito un técnico',
                sublabel: 'Solicitar servicio',
                onLogin: () => Navigator.push(
                  context,
                  _fade(const LoginScreen()),
                ),
                onRegister: () => Navigator.push(
                  context,
                  _fade(const RegisterClientScreen()),
                ),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.handyman_rounded,
                label: 'Soy técnico',
                sublabel: 'Ofrecer servicios',
                onLogin: () => Navigator.push(
                  context,
                  _fade(const LoginScreen(mode: LoginMode.technician)),
                ),
                onRegister: () => Navigator.push(
                  context,
                  _fade(const RegisterTechnicianScreen()),
                ),
              ),

              const Spacer(),

              // ── Secondary row ──────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _GhostButton(
                    icon: Icons.support_agent_outlined,
                    label: 'PQR',
                    onTap: () => Navigator.push(
                      context,
                      _fade(const PqrScreen()),
                    ),
                  ),
                  _GhostButton(
                    icon: Icons.shield_outlined,
                    label: 'Admin',
                    onTap: () => Navigator.push(
                      context,
                      _fade(const LoginScreen(mode: LoginMode.admin)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  PageRouteBuilder<T> _fade<T>(Widget page) => PageRouteBuilder(
        pageBuilder: (context, animation, _) => page,
        transitionsBuilder: (context, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 180),
      );
}

// ─── Role card ──────────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onLogin,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accent, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: const TextStyle(fontSize: 12, color: _textMuted),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                TextButton(
                  onPressed: onLogin,
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Entrar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: onRegister,
                  style: TextButton.styleFrom(
                    foregroundColor: _textMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Registro', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ghost button ────────────────────────────────────────────────────────────
class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: _textMuted),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: _textMuted)),
          ],
        ),
      ),
    );
  }
}