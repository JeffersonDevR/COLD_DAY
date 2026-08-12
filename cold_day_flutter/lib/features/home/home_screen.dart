import 'package:flutter/material.dart';
import 'package:cold_day_flutter/features/auth/login_screen.dart';
import 'package:cold_day_flutter/features/pqr/pqr_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              // Logo
              Container(
                height: 110,
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.ac_unit,
                    size: 80,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cold Day',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Multi servicios técnicos',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Color(0xFF90CAF9)),
              ),
              const SizedBox(height: 2),
              const Text(
                'Conectamos soluciones, generamos confianza.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF90CAF9),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 36),

              // Opción 1: Solicitar un servicio
              _HomeOptionCard(
                icon: Icons.build_circle_outlined,
                title: 'Solicitar un servicio',
                subtitle: 'Pedí un técnico para tu equipo',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Opción 2: Soy un técnico
              _HomeOptionCard(
                icon: Icons.handyman_outlined,
                title: 'Soy un técnico',
                subtitle: 'Ofrecé tus servicios y recibí solicitudes',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(
                        mode: LoginMode.technician,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Opción 3: Soy un proveedor
              _HomeOptionCard(
                icon: Icons.storefront_outlined,
                title: 'Soy un proveedor',
                subtitle: 'Administrá tu negocio y tus técnicos',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(
                        mode: LoginMode.provider,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // PQR
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber.shade300,
                  side: BorderSide(color: Colors.amber.shade300),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PqrScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.support_agent),
                label: const Text(
                  'PQR · Quejas y reclamos',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: Colors.blueAccent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D1B3E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.blueGrey),
            ],
          ),
        ),
      ),
    );
  }
}