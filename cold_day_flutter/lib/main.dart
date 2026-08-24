import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/auth/auth_router.dart';
import 'package:cold_day_flutter/core/theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Day ❄️',
      themeMode: ThemeMode.system,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Routing por rol en el arranque (HU-AUTH-003): si hay una sesión guardada,
/// la app abre directo el flujo del rol autenticado; si no, abre la landing.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _hasSession;

  @override
  void initState() {
    super.initState();
    _hasSession = _restoreSession();
  }

  Future<bool> _restoreSession() async {
    try {
      if (!await TokenStore.hasSession()) return false;
      final role = await TokenStore.readRole();
      if (!mounted) return false;
      _routeByRole(role);
      return true;
    } catch (_) {
      // Sin plataforma de almacenamiento (tests, web sin plugin): landing.
      return false;
    }
  }

  void _routeByRole(String? role) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => roleHome(role)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data == true) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return roleHome(null); // landing
      },
    );
  }
}
