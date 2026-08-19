// Smoker test de la app (RF-LAND-001): MyApp sigue siendo una landing funcional
// (logo + tagline + tarjetas de rol). Repara el counter test por defecto que ya
// no aplica contra MyApp (landing real, RF-LAND-005).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/main.dart';

void main() {
  testWidgets('MyApp renders the Cold Day landing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Cold Day'), findsOneWidget);
    expect(find.text('Solicitar un servicio'), findsOneWidget);
    expect(find.text('Soy un técnico'), findsOneWidget);
    expect(find.text('Multi servicios técnicos'), findsOneWidget);
  });
}