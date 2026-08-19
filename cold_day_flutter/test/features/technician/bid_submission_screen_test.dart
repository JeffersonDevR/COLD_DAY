// Formulario de oferta real (RF-TEC-006, RF-SR-002): BidSubmissionScreen envía
// el bid con costos de traslado + diagnóstico al endpoint real y sale con
// éxito cuando el POST responde 201.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/technician/bid_submission_screen.dart';

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-tech',
      'auth.refresh_token': 'refresh-tech',
      'auth.role': 'technician',
      'auth.user_id': 2,
    });
  });

  testWidgets('muestra el formulario con los costos del bid', (tester) async {
    ApiClient.setClient(FakeClient((request) {
      fail('No se esperaban peticiones: ${request.url.path}');
    }));

    await tester.pumpWidget(const MaterialApp(
      home: BidSubmissionScreen(requestId: 42, equipment: 'Nevera clásica'),
    ));

    expect(find.byType(Form), findsOneWidget);
    expect(find.text('Costo de traslado (COP)'), findsOneWidget);
    expect(find.text('Costo de diagnóstico (COP)'), findsOneWidget);
  });

  testWidgets('enviar oferta POSTea el bid con costos y request_id correctos',
      (tester) async {
    Map<String, dynamic>? bidPayload;
    ApiClient.setClient(FakeClient((request) {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/services/bids/');
      expect(request.headers['Authorization'], 'Bearer tok-tech');
      bidPayload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'message': 'ok', 'bid_id': 9, 'status': 'pending'}),
        201,
      );
    }));

    await tester.pumpWidget(const MaterialApp(
      home: BidSubmissionScreen(requestId: 42, equipment: 'Nevera clásica'),
    ));

    await tester.enterText(
      find.widgetWithText(TextField, 'Costo de traslado (COP)'),
      '20000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Costo de diagnóstico (COP)'),
      '30000',
    );
    await tester.tap(find.text('Enviar oferta'));
    await tester.pumpAndSettle();

    expect(bidPayload, isNotNull);
    expect(bidPayload!['service_request_id'], 42);
    expect(bidPayload!['transport_cost'], 20000);
    expect(bidPayload!['diagnosis_cost'], 30000);
    expect(bidPayload!.containsKey('technician_id'), isFalse);

    // Éxito: la pantalla sale devolviendo `true` (el dashboard muestra el SnackBar).
    expect(find.byType(BidSubmissionScreen), findsNothing);
  });
}