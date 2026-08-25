import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/radar/technician_map_screen.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.response);

  final http.Response response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.url.path, '/api/technicians/requests/nearby/');
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-tech',
      'auth.role': 'technician',
    });
  });

  testWidgets('shows a usable map and nearby request marker data', (
    tester,
  ) async {
    ApiClient.setClient(
      _FakeClient(
        http.Response(
          jsonEncode({
            'requests': [
              {
                'id': 7,
                'equipment': 'Nevera',
                'description': 'No enfría',
                'latitude': 7.8939,
                'longitude': -72.5078,
                'status': 'requested',
              },
            ],
          }),
          200,
        ),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: TechnicianMapScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(GoogleMap), findsOneWidget);
    expect(find.text('Nevera'), findsOneWidget);
    expect(find.textContaining('No enfría'), findsOneWidget);
  });

  testWidgets('reports requests with invalid coordinates', (tester) async {
    ApiClient.setClient(
      _FakeClient(
        http.Response(
          jsonEncode({
            'requests': [
              {'id': 7, 'latitude': 999, 'longitude': -72.5},
            ],
          }),
          200,
        ),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: TechnicianMapScreen()));
    await tester.pumpAndSettle();

    expect(
      find.text('No hay solicitudes con ubicación válida'),
      findsOneWidget,
    );
  });

  testWidgets('list selection opens request details and offer action', (
    tester,
  ) async {
    ApiClient.setClient(
      _FakeClient(
        http.Response(
          jsonEncode({
            'requests': [
              {
                'id': 8,
                'equipment': 'Aire',
                'description': 'Revisar unidad',
                'latitude': 7.89,
                'longitude': -72.50,
                'status': 'requested',
                'service_type': 'repair',
                'distance_km': 1.4,
              },
            ],
          }),
          200,
        ),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: TechnicianMapScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aire'));
    await tester.pump();

    expect(find.text('Ubicación disponible'), findsOneWidget);
    expect(find.text('Enviar oferta'), findsOneWidget);
  });
}
