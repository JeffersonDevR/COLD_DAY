// Registro navegable (RF-LAND-002/003): los CTAs de registro del landing y del
// login navegan a formularios reales (no a un SnackBar "próximamente").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cold_day_flutter/features/auth/login_screen.dart';
import 'package:cold_day_flutter/features/auth/register_client_screen.dart';
import 'package:cold_day_flutter/features/auth/register_technician_screen.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';

void main() {
  testWidgets('landing: "Regístrate como cliente" navega al registro de cliente',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    await tester.tap(find.text('Regístrate como cliente'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterClientScreen), findsOneWidget);
  });

  testWidgets('landing: "Regístrate como técnico" navega al registro de técnico',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    await tester.tap(find.text('Regístrate como técnico'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterTechnicianScreen), findsOneWidget);
  });

  testWidgets('login de técnico: el link de registro abre el registro de técnico',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(mode: LoginMode.technician)),
    );

    await tester.tap(find.text('¿No tenés cuenta? Registrate como técnico'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterTechnicianScreen), findsOneWidget);
  });

  testWidgets('login de cliente: el link de registro abre el registro de cliente',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(mode: LoginMode.client)),
    );

    await tester.tap(find.text('¿No tenés cuenta? Registrate'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterClientScreen), findsOneWidget);
  });
}