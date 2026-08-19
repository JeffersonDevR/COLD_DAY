// Radar del técnico con costos (RF-MATCH-006, RF-SR-002, RF-TEC-006).
// El radar pega al endpoint real /api/services/technicians-nearby/, muestra el
// área vacía con el mensaje de RF-MATCH-007 y el diálogo de oferta envía el bid
// con transport_cost + diagnosis_cost (mensaje "¡Oferta enviada!", no "asignado").
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/radar/technician_radar_screen.dart';

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

Map<String, dynamic> _technicianJson(int id, String name, double rating) => {
      'id': id,
      'name': name,
      'rating': rating,
      'specialty': 'Neveras',
      'distance_km': 1.2,
    };

Widget _screen({required double latitude, required double longitude}) =>
    MaterialApp(
      home: TechnicianRadarScreen(
        requestId: 42,
        latitude: latitude,
        longitude: longitude,
      ),
    );

void main() {
  testWidgets('radar carga técnicos del endpoint real y los muestra',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      expect(request.url.path, '/api/services/technicians-nearby/');
      return http.Response(
        jsonEncode({
          'count': 2,
          'technicians': [
            _technicianJson(7, 'Carlos Tecnico', 4.5),
            _technicianJson(8, 'Lucía Fría', 4.9),
          ],
        }),
        200,
      );
    }));

    await tester.pumpWidget(_screen(latitude: 7.8939, longitude: -72.5078));
    await tester.pumpAndSettle();

    expect(find.text('Carlos Tecnico'), findsOneWidget);
    expect(find.text('Lucía Fría'), findsOneWidget);
    expect(find.textContaining('4.5'), findsOneWidget);
    expect(find.textContaining('1.2 km'), findsNWidgets(2));
  });

  testWidgets('radar sin técnicos muestra el mensaje de área vacía',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(
        jsonEncode({'count': 0, 'technicians': []}),
        200,
      );
    }));

    await tester.pumpWidget(_screen(latitude: 7.8939, longitude: -72.5078));
    await tester.pumpAndSettle();

    expect(find.text('No se encontraron técnicos en tu área'), findsOneWidget);
  });

  testWidgets('diálogo de oferta envía el bid con costos y muestra "¡Oferta enviada!"',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-s2',
      'auth.refresh_token': 'refresh-s2',
      'auth.role': 'client',
      'auth.user_id': 1,
    });

    Map<String, dynamic>? bidPayload;
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/services/bids/') {
        bidPayload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'message': 'ok', 'bid_id': 9, 'status': 'pending'}),
          201,
        );
      }
      return http.Response(
        jsonEncode({
          'count': 1,
          'technicians': [_technicianJson(7, 'Carlos Tecnico', 4.5)],
        }),
        200,
      );
    }));

    await tester.pumpWidget(_screen(latitude: 7.8939, longitude: -72.5078));
    await tester.pumpAndSettle();

    // Abrir el diálogo de oferta (botón de la tarjeta).
    await tester.tap(find.text('Enviar oferta'));
    await tester.pumpAndSettle();
    expect(find.text('Costo de traslado (COP)'), findsOneWidget);
    expect(find.text('Costo de diagnóstico (COP)'), findsOneWidget);

    // Costos editados por el usuario.
    await tester.enterText(
      find.widgetWithText(TextField, 'Costo de traslado (COP)'),
      '20000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Costo de diagnóstico (COP)'),
      '30000',
    );
    await tester.tap(find.text('Enviar oferta').last);
    await tester.pumpAndSettle();

    // El bid viaja con los costos y el request_id correcto.
    expect(bidPayload, isNotNull);
    expect(bidPayload!['service_request_id'], 42);
    expect(bidPayload!['transport_cost'], 20000);
    expect(bidPayload!['diagnosis_cost'], 30000);
    expect(bidPayload!.containsKey('technician_id'), isFalse);

    // Mensaje de éxito: "oferta enviada", no "asignado".
    expect(find.text('¡Oferta enviada!'), findsOneWidget);
    expect(find.textContaining('Servicio Asignado'), findsNothing);
  });
}
