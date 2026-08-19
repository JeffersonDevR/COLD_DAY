// Dashboard del técnico (HU-SR-002): radar real de solicitudes cercanas
// (GET /api/technicians/requests/nearby/, RF-MATCH-004) y navegación según el
// estado de cada solicitud a ofertar / diagnóstico / pacto / finalizar.
// Las acciones se derivan del estado (status + my_bid_status) que devuelve el
// radar, con el backend real en producción y FakeClient en los tests.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/technician/technician_dashboard.dart';

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

Map<String, dynamic> _requestJson({
  required int id,
  required String status,
  String? myBidStatus,
  String equipment = 'Nevera clásica',
  String description = 'No enfría',
}) =>
    {
      'id': id,
      'equipment': equipment,
      'description': description,
      'latitude': 7.8939,
      'longitude': -72.5078,
      'status': status,
      'my_bid_status': myBidStatus,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-tech',
      'auth.refresh_token': 'refresh-tech',
      'auth.role': 'technician',
      'auth.user_id': 2,
    });
  });

  testWidgets('dashboard carga el radar real y muestra las solicitudes',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/technicians/requests/nearby/');
      expect(request.url.queryParameters['radius_km'], '10.0');
      expect(request.headers['Authorization'], 'Bearer tok-tech');
      return http.Response(
        jsonEncode({
          'requests': [
            _requestJson(id: 10, status: 'requested'),
            _requestJson(id: 11, status: 'bidding'),
          ],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    // Equipo + descripción + estado en español (spec: estados de negocio en español).
    expect(find.text('Nevera clásica'), findsNWidgets(2));
    expect(find.text('No enfría'), findsNWidgets(2));
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('En oferta'), findsOneWidget);
  });

  testWidgets('radar vacío muestra mensaje de área sin solicitudes',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(jsonEncode({'requests': []}), 200);
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    expect(find.text('No hay solicitudes cercanas'), findsOneWidget);
  });

  testWidgets('solicitud sin oferta navega a la pantalla de oferta (bid)',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(
        jsonEncode({
          'requests': [_requestJson(id: 10, status: 'requested')],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar oferta'));
    await tester.pumpAndSettle();

    // Navegó a BidSubmissionScreen (AppBar propio).
    expect(find.text('Enviar Oferta'), findsOneWidget);
  });

  testWidgets('ciclo de oferta: enviar bid muestra "¡Oferta enviada!" y recarga',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/services/bids/') {
        return http.Response(
          jsonEncode({'message': 'ok', 'bid_id': 9, 'status': 'pending'}),
          201,
        );
      }
      return http.Response(
        jsonEncode({
          'requests': [_requestJson(id: 10, status: 'requested')],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar oferta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar oferta').last); // botón del formulario
    await tester.pumpAndSettle();

    // Volvió al dashboard con el SnackBar de éxito.
    expect(find.text('¡Oferta enviada!'), findsOneWidget);
    expect(find.byType(TechnicianDashboard), findsOneWidget);
  });

  testWidgets('solicitud con oferta ya enviada no ofrece duplicar (RF-MATCH-005)',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(
        jsonEncode({
          'requests': [
            _requestJson(id: 10, status: 'bidding', myBidStatus: 'pending'),
          ],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    expect(find.text('Oferta enviada'), findsOneWidget);
    expect(find.text('Enviar oferta'), findsNothing);
  });

  testWidgets('solicitud en diagnóstico navega a la pantalla de diagnóstico',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(
        jsonEncode({
          'requests': [
            _requestJson(id: 12, status: 'diagnosis', myBidStatus: 'accepted'),
          ],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar diagnóstico'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnóstico'), findsOneWidget);
  });

  testWidgets('solicitud con pacto pendiente navega a proponer pacto',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(
        jsonEncode({
          'requests': [
            _requestJson(id: 13, status: 'pact_proposed', myBidStatus: 'accepted'),
          ],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Proponer pacto'));
    await tester.pumpAndSettle();

    expect(find.text('Proponer Pacto'), findsOneWidget);
  });

  testWidgets('solicitud en proceso se finaliza con confirmación',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-tech',
      'auth.refresh_token': 'refresh-tech',
      'auth.role': 'technician',
      'auth.user_id': 2,
    });

    String? completedPath;
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/services/12/complete') {
        completedPath = request.url.path;
        expect(request.headers['Authorization'], 'Bearer tok-tech');
        return http.Response(
          jsonEncode({'message': 'Servicio completado', 'request_id': 12, 'status': 'completed'}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'requests': [
            _requestJson(id: 12, status: 'in_progress', myBidStatus: 'accepted'),
          ],
        }),
        200,
      );
    }));

    await tester.pumpWidget(const MaterialApp(home: TechnicianDashboard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finalizar servicio'));
    await tester.pumpAndSettle();
    // Diálogo de confirmación.
    expect(find.text('¿Finalizar el servicio?'), findsOneWidget);
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();

    expect(completedPath, '/api/services/12/complete');
    expect(find.text('Servicio completado'), findsOneWidget);
  });
}
