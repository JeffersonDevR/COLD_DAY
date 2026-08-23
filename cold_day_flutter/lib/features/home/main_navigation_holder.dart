import 'package:flutter/material.dart';
import 'package:cold_day_flutter/features/admin/admin_dashboard_screen.dart';
import 'package:cold_day_flutter/features/request/simple_request_screen.dart';
import 'package:cold_day_flutter/features/request/client_history_screen.dart';
import 'package:cold_day_flutter/features/profile/profile_screen.dart';
import 'package:cold_day_flutter/features/technician/technician_dashboard.dart';

class MainNavigationHolder extends StatefulWidget {
  final String role;

  const MainNavigationHolder({super.key, required this.role});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  List<Widget> get _screens {
    switch (widget.role) {
      case 'client':
        return [
          const SimpleRequestScreen(),
          const ClientServicesTabScreen(),
          const ProfileScreen(),
        ];
      case 'technician':
        return [
          TechnicianDashboard(), // Home/List and real request radar
          TechnicianDashboard(), // Radar, backed by /technicians/requests/nearby/
          const ProfileScreen(),
        ];
      case 'admin':
        return [
          const AdminDashboardScreen(), // Home/KPIs
          const AdminTechniciansScreen(), // Verification Management
          const ProfileScreen(),
        ];
      default:
        return [const Scaffold(body: Center(child: Text('Acceso denegado')))];
    }
  }

  List<BottomNavigationBarItem> get _navItems {
    switch (widget.role) {
      case 'client':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Servicios',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ];
      case 'technician':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Radar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ];
      case 'admin':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'KPIs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Técnicos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: _navItems,
      ),
    );
  }
}

// ─── CLIENTE: TABS DE SERVICIOS (ACTIVAS / INACTIVAS) ──────────────────────────
class ClientServicesTabScreen extends StatelessWidget {
  const ClientServicesTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis Servicios'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Activas'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ClientHistoryScreen(filterActive: true),
            ClientHistoryScreen(filterActive: false),
          ],
        ),
      ),
    );
  }
}

// ─── ADMIN: TABS DE GESTION DE TECNICOS (PENDIENTES / VERIFICADOS) ─────────────
class AdminTechniciansScreen extends StatelessWidget {
  const AdminTechniciansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestión de Técnicos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Por Verificar'),
              Tab(text: 'Verificados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminTechniciansListScreen(showPendingOnly: true),
            AdminTechniciansListScreen(showPendingOnly: false),
          ],
        ),
      ),
    );
  }
}
