// Smoker tests de la app (RF-LAND-001/005): MyApp sigue siendo una landing
// funcional (logo + tagline + tarjetas de rol) y el flujo core del cliente es
// alcanzable: Equipo -> Solicitud -> Radar (sin dead-end estático).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/simple_request_screen.dart';
import 'package:cold_day_flutter/main.dart';

class FakeClient extends http.BaseClient {
  final http.Response Function(http.Request) onRequest;
  FakeClient(this.onRequest);

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

Map<String, dynamic> _catalog() => {
      'categories': [
        {
          'id': 1,
          'name': 'Neveras',
          'icon': 'kitchen',
          'technologies': ['conventional'],
          'residential': [
            {'id': 1, 'name': 'Nevera clásica', 'description': 'Nevera básica'},
          ],
          'industrial': [],
        }
      ],
    };

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  testWidgets('MyApp renders the Cold Day landing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Cold Day'), findsOneWidget);
    expect(find.text('Solicitar un servicio'), findsOneWidget);
    expect(find.text('Soy un técnico'), findsOneWidget);
    expect(find.text('Multi servicios técnicos'), findsOneWidget);
  });

  // RF-LAND-005: cliente logueado navega Equipo -> Solicitud -> Radar.
  testWidgets('core flow: equipment -> request -> radar (no dead-end)',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-flow',
      'auth.refresh_token': 'refresh-flow',
      'auth.role': 'client',
      'auth.user_id': 1,
    });

    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/catalog/') {
        return http.Response(jsonEncode(_catalog()), 200);
      }
      if (request.url.path == '/api/services/' && request.method == 'POST') {
        expect(request.headers['Authorization'], 'Bearer tok-flow');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('user_id'), isFalse);
        return http.Response(
          jsonEncode({
            'message': 'ok',
            'request_id': 42,
            'status': 'requested',
          }),
          201,
        );
      }
      if (request.url.path == '/api/services/technicians-nearby/') {
        return http.Response(
          jsonEncode({'count': 0, 'technicians': []}),
          200,
        );
      }
      fail('Unexpected request: ${request.method} ${request.url.path}');
    }));

    await tester.pumpWidget(const MaterialApp(home: SimpleRequestScreen()));
    await tester.pumpAndSettle();

    // The screen should show "¿Qué necesitás?"
    expect(find.text('¿Qué necesitás?'), findsOneWidget);

    // Wait for catalog to load
    await tester.pumpAndSettle();

    // Fill in the description
    await tester.enterText(
      find.byType(TextField).first,
      'Nevera no enfria',
    );

    // Scroll down to the button
    await tester.ensureVisible(find.text('Buscar técnicos'));
    await tester.tap(find.text('Buscar técnicos'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // The map screen should open
    expect(find.text('Mapa de Técnicos #42'), findsOneWidget);
  });
}
