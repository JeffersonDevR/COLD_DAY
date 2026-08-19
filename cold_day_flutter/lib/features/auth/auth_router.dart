// Rutas por rol (HU-AUTH-003): tras un login exitoso o al restaurar una sesión
// guardada, la app muestra únicamente el flujo del rol autenticado.
//
// - client     -> selección de equipo (flujo de solicitud de servicio)
// - technician -> dashboard del técnico
// - admin      -> placeholder hasta S5 (admin-dashboard)
// - sin rol    -> landing (HomeScreen)
import 'package:flutter/material.dart';

import 'package:cold_day_flutter/features/equipment/equipment_selection_screen.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/placeholder/coming_soon_screen.dart';
import 'package:cold_day_flutter/features/technician/technician_dashboard.dart';

Widget roleHome(String? role) {
  switch (role) {
    case 'client':
      return const EquipmentSelectionScreen();
    case 'technician':
      return TechnicianDashboard();
    case 'admin':
      return const ComingSoonScreen(
        title: 'Panel de administración',
        message: 'La consola de administración llega próximamente.',
      );
    default:
      return const HomeScreen();
  }
}