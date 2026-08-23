import 'package:flutter/material.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userProfile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ApiClient.me();
      setState(() {
        _userProfile = profile;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar perfil';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final token = await TokenStore.readRefreshToken();
    if (token != null) {
      try {
        await ApiClient.logout(token);
      } catch (_) {}
    }
    await TokenStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadProfile, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final user = _userProfile?['user'] as Map<String, dynamic>? ?? {};
    final name = user['full_name'] as String? ?? 'Usuario';
    final document = user['document'] as String? ?? 'N/A';
    final phone = user['phone'] as String? ?? 'N/A';
    final role = user['role'] as String? ?? 'client';

    // Para técnicos
    final specialty = _userProfile?['specialty'] as String? ?? 'No especificado';
    final status = _userProfile?['verification_status'] as String? ?? 'pending';

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            
            // Avatar
            Center(
              child: CircleAvatar(
                radius: 46,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                child: Text(
                  name[0].toUpperCase(),
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              role == 'client'
                  ? 'Cliente'
                  : role == 'technician'
                      ? 'Técnico'
                      : 'Administrador',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            
            const SizedBox(height: 32),
            
            // Info básica
            _InfoTile(label: 'Documento (CC)', value: document),
            _InfoTile(label: 'Teléfono', value: phone),
            
            // Si es técnico, muestra certificaciones
            if (role == 'technician') ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Certificaciones y Estado',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _InfoTile(label: 'Especialidad', value: specialty),
              _InfoTile(
                label: 'Estado de Verificación',
                value: status == 'verified'
                    ? 'Aprobado ✅'
                    : status == 'rejected'
                        ? 'Rechazado ❌'
                        : 'En revisión ⏳',
              ),
            ],
            
            const SizedBox(height: 48),
            
            // Cerrar Sesión
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111928) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.hintColor, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
