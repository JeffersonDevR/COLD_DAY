import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/tracking/tracking_screen.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.response);
  final http.Response response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth.access_token': 'token'});
  });

  Future<void> pumpTracking(WidgetTester tester, http.Response response) async {
    ApiClient.setClient(_FakeClient(response));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const MaterialApp(
        home: TrackingScreen(requestId: 7, clientLat: 7.89, clientLon: -72.5),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows no-location state and honest tracking scope', (
    tester,
  ) async {
    await pumpTracking(
      tester,
      http.Response(
        jsonEncode({'latitude': null, 'longitude': null, 'updated_at': null}),
        200,
      ),
    );

    expect(
      find.text('El técnico todavía no publicó su ubicación.'),
      findsOneWidget,
    );
    expect(
      find.text('Solo ubicación en vivo. No incluye ETA ni ruta.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Centrar el mapa en la última ubicación válida'),
      findsOneWidget,
    );
  });

  testWidgets('shows API error and invalid-coordinate state', (tester) async {
    await pumpTracking(tester, http.Response('{}', 500));
    expect(find.text('No se pudo actualizar la ubicación.'), findsOneWidget);

    await pumpTracking(
      tester,
      http.Response(
        jsonEncode({'latitude': 999, 'longitude': -72.5, 'updated_at': null}),
        200,
      ),
    );
    expect(
      find.text('La ubicación recibida no tiene coordenadas válidas.'),
      findsOneWidget,
    );
  });
}
