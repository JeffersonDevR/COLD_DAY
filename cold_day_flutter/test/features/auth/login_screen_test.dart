// RED (task 1.8, RF-LAND-004): el fake login (cualquier credencial entra) se
// elimina. Contra un FakeClient que responde 401, la app DEBE mostrar error de
// autenticación y NO navegar. Con un login exitoso, debe rutear por rol.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/auth/login_screen.dart';
import 'package:cold_day_flutter/features/request/simple_request_screen.dart';
import 'package:cold_day_flutter/features/equipment/equipment_selection_screen.dart';
import 'package:cold_day_flutter/features/technician/technician_dashboard.dart';

class FakeApiClient extends http.BaseClient {
  final http.Response Function(http.Request request) onRequest;
  FakeApiClient(this.onRequest);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = onRequest(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

const _catalogResponse =
    '{"categories": [{"id": 1, "name": "Aire acondicionado", "icon": "snow", "technologies": [], "residential": [], "industrial": []}]}';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'login con credenciales arbitrarias contra FakeClient 401 muestra error y '
    'NO entra a ningún flujo',
    (WidgetTester tester) async {
      ApiClient.setClient(
        FakeApiClient((request) {
          if (request.url.path == '/api/auth/login') {
            return http.Response(
              jsonEncode({'detail': 'Credenciales inválidas'}),
              401,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      await tester.pumpWidget(
        const MaterialApp(home: LoginScreen(mode: LoginMode.client)),
      );

      await tester.enterText(
        find.byKey(const Key('login_document')),
        '1123456789',
      );
      await tester.enterText(
        find.byKey(const Key('login_password')),
        'CualquierClave123',
      );
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();

      // El error de autenticación se muestra…
      expect(find.text('Documento o contraseña incorrectos.'), findsOneWidget);
      // …y la app NO navega a ningún flujo.
      expect(find.byType(SimpleRequestScreen), findsNothing);
      expect(find.byType(TechnicianDashboard), findsNothing);
    },
  );

  testWidgets('login exitoso como técnico navega al dashboard del técnico', (
    WidgetTester tester,
  ) async {
    ApiClient.setClient(
      FakeApiClient((request) {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'role': 'technician',
              'user_id': 2,
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(mode: LoginMode.technician)),
    );

    await tester.enterText(
      find.byKey(const Key('login_document')),
      '1098765432',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      'TecnicoPass1',
    );
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.byType(TechnicianDashboard), findsOneWidget);
  });

  testWidgets('login exitoso como cliente navega a la selección de equipo', (
    WidgetTester tester,
  ) async {
    ApiClient.setClient(
      FakeApiClient((request) {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'role': 'client',
              'user_id': 1,
            }),
            200,
          );
        }
        if (request.url.path == '/api/catalog/') {
          return http.Response(_catalogResponse, 200);
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(mode: LoginMode.client)),
    );

    await tester.enterText(
      find.byKey(const Key('login_document')),
      '1123456789',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      'ClientePass1',
    );
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.byType(EquipmentSelectionScreen), findsOneWidget);
  });
}
