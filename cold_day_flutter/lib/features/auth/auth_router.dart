// Rutas por rol (HU-AUTH-003): tras un login exitoso o al restaurar una sesión
// guardada, la app muestra únicamente el flujo del rol autenticado.
//
// - client     -> selección de equipo (flujo de solicitud de servicio)
// - technician -> dashboard del técnico
// - admin      -> dashboard de administración (S5, HU-ADM-001/002)
// - sin rol    -> landing (HomeScreen)
import 'package:flutter/material.dart';

import 'package:cold_day_flutter/features/admin/admin_dashboard_screen.dart';
// ignore: unused_import
import 'package:cold_day_flutter/features/equipment/equipment_selection_screen.dart';
import 'package:cold_day_flutter/features/request/simple_request_screen.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';
import 'package:cold_day_flutter/features/technician/technician_dashboard.dart';

import 'package:cold_day_flutter/features/home/main_navigation_holder.dart';

Widget roleHome(String? role) {
  switch (role) {
    case 'client':
      return const MainNavigationHolder(role: 'client');
    case 'technician':
      return const MainNavigationHolder(role: 'technician');
    case 'admin':
      return const MainNavigationHolder(role: 'admin');
    default:
      return const HomeScreen();
  }
}