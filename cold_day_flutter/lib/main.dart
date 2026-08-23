import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/network/token_store.dart';
import 'package:cold_day_flutter/features/auth/auth_router.dart';

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
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0284C7),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080F1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5BC8F5),
          onPrimary: Color(0xFF080F1E),
          surface: Color(0xFF111928),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ),
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