import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/simple_request_screen.dart';

class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path == '/api/catalog/'
        ? {'categories': []}
        : {'requests': []};
    final response = http.Response(jsonEncode(body), 200);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  testWidgets('home del cliente presenta acción principal y resumen vacío', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'client-token',
      'auth.role': 'client',
    });
    ApiClient.setClient(_FakeClient());

    await tester.pumpWidget(const MaterialApp(home: SimpleRequestScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Solicita un servicio'), findsOneWidget);
    expect(find.text('0 servicio(s) activo(s)'), findsOneWidget);
    expect(find.text('Buscar técnicos'), findsOneWidget);
    expect(find.byTooltip('Mis servicios'), findsOneWidget);
  });
}
