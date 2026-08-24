// Historial del cliente (RF-SR-010, HU-SR-001/003): listado propio desde
// GET /api/services/my y detalle con línea de tiempo (bids + pactos) desde
// GET /api/services/{id}. Acciones: aceptar/rechazar pacto (PactReviewDialog),
// aceptar oferta y cancelar solicitud.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/request/client_history_screen.dart';

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

Map<String, dynamic> _summaryJson({
  required int id,
  required String status,
  String? technicianName,
}) => {
  'id': id,
  'status': status,
  'service_type': 'repair',
  'description': 'No enfría',
  'equipment': 'Nevera clásica',
  'created_at': '2026-08-18T10:00:00',
  'budget_offered': 80000,
  'technician': technicianName == null
      ? null
      : {
          'id': 7,
          'name': technicianName,
          'rating': 4.5,
          'specialty': 'Neveras',
        },
};

Map<String, dynamic> _detailJson({
  required int id,
  required String status,
  String bidStatus = 'accepted',
  String pactStatus = 'proposed',
}) => {
  'id': id,
  'status': status,
  'service_type': 'repair',
  'description': 'No enfría',
  'equipment': {'id': 1, 'name': 'Nevera clásica', 'sector': 'residential'},
  'created_at': '2026-08-18T10:00:00',
  'budget_offered': 80000,
  'diagnosis_observations': 'Fuga de gas refrigerante',
  'technician': {
    'id': 7,
    'name': 'Carlos Tecnico',
    'rating': 4.5,
    'specialty': 'Neveras',
  },
  'timeline': {
    'bids': [
      {
        'id': 3,
        'technician_id': 7,
        'technician_name': 'Carlos Tecnico',
        'price_offered': 50000,
        'transport_cost': 15000,
        'diagnosis_cost': 35000,
        'estimated_time_minutes': 45,
        'status': bidStatus,
        'created_at': '2026-08-18T11:00:00',
      },
    ],
    'agreements': [
      {
        'id': 5,
        'technician_id': 7,
        'labor_cost': 80000,
        'transport_cost': 15000,
        'diagnosis_cost': 35000,
        'total': 130000,
        'observations': 'Fuga de gas refrigerante',
        'status': pactStatus,
        'created_at': '2026-08-18T12:00:00',
        'decided_at': null,
      },
    ],
  },
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-client',
      'auth.refresh_token': 'refresh-client',
      'auth.role': 'client',
      'auth.user_id': 1,
    });
  });

  testWidgets('historial lista mis solicitudes desde /api/services/my', (
    tester,
  ) async {
    ApiClient.setClient(
      FakeClient((request) {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/services/my');
        expect(request.headers['Authorization'], 'Bearer tok-client');
        return http.Response(
          jsonEncode({
            'requests': [
              _summaryJson(id: 10, status: 'bidding'),
              _summaryJson(
                id: 11,
                status: 'completed',
                technicianName: 'Carlos Tecnico',
              ),
            ],
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nevera clásica'), findsNWidgets(2));
    expect(find.text('En oferta'), findsOneWidget);
    expect(find.text('Completada'), findsOneWidget);
    expect(find.text('Carlos Tecnico'), findsOneWidget);
  });

  testWidgets('historial vacío muestra mensaje', (tester) async {
    ApiClient.setClient(
      FakeClient((request) {
        return http.Response(jsonEncode({'requests': []}), 200);
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes solicitudes'), findsOneWidget);
  });

  testWidgets('detalle muestra la línea de tiempo (técnico, bid y pacto)', (
    tester,
  ) async {
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'pact_proposed')],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/services/10');
        return http.Response(
          jsonEncode(_detailJson(id: 10, status: 'pact_proposed')),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    // Técnico asignado (header interpolado + tile del bid), desglose del pacto.
    expect(find.textContaining('Carlos Tecnico'), findsNWidgets(2));
    expect(find.textContaining('Fuga de gas refrigerante'), findsWidgets);
    expect(find.text('\$130.000'), findsOneWidget); // total del pacto
  });

  testWidgets('aceptar oferta POSTea al endpoint de accept del bid', (
    tester,
  ) async {
    String? acceptedPath;
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/10/bids/3/accept') {
          acceptedPath = request.url.path;
          return http.Response(
            jsonEncode({
              'message': 'Oferta aceptada',
              'request_id': 10,
              'status': 'diagnosis',
              'technician_id': 7,
            }),
            200,
          );
        }
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'bidding')],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(
            _detailJson(id: 10, status: 'bidding', bidStatus: 'pending'),
          ),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar oferta'));
    await tester.pumpAndSettle();

    expect(acceptedPath, '/api/services/10/bids/3/accept');
    expect(find.text('Oferta aceptada'), findsWidgets);
  });

  testWidgets('aceptar pacto desde el diálogo de revisión', (tester) async {
    String? acceptPath;
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/10/agreements/5/accept') {
          acceptPath = request.url.path;
          return http.Response(
            jsonEncode({
              'message': 'Pacto aceptado, el servicio está en proceso',
              'request_id': 10,
              'status': 'in_progress',
            }),
            200,
          );
        }
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'pact_proposed')],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(_detailJson(id: 10, status: 'pact_proposed')),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    // El diálogo muestra el desglose del pacto.
    await tester.tap(find.text('Revisar pacto'));
    await tester.pumpAndSettle();
    expect(find.text('Mano de obra'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);

    await tester.tap(find.text('Aceptar pacto'));
    await tester.pumpAndSettle();

    expect(acceptPath, '/api/services/10/agreements/5/accept');
    expect(
      find.text('Pacto aceptado, el servicio está en proceso'),
      findsWidgets,
    );
  });

  testWidgets('rechazar pacto POSTea al endpoint de reject', (tester) async {
    String? rejectPath;
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/10/agreements/5/reject') {
          rejectPath = request.url.path;
          return http.Response(
            jsonEncode({
              'message':
                  'Pacto rechazado, las ofertas vuelven a estar disponibles',
              'request_id': 10,
              'status': 'bidding',
            }),
            200,
          );
        }
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'pact_proposed')],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(_detailJson(id: 10, status: 'pact_proposed')),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisar pacto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rechazar pacto'));
    await tester.pumpAndSettle();

    expect(rejectPath, '/api/services/10/agreements/5/reject');
    expect(
      find.text('Pacto rechazado, las ofertas vuelven a estar disponibles'),
      findsWidgets,
    );
  });

  testWidgets('cancelar solicitud confirma y POSTea al endpoint de cancel', (
    tester,
  ) async {
    String? cancelPath;
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/10/cancel') {
          cancelPath = request.url.path;
          return http.Response(
            jsonEncode({
              'message': 'Solicitud cancelada',
              'request_id': 10,
              'status': 'cancelled',
            }),
            200,
          );
        }
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'requested')],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(_detailJson(id: 10, status: 'requested')),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cancelar la solicitud?'), findsOneWidget);
    await tester.tap(find.text('Sí, cancelar'));
    await tester.pumpAndSettle();

    expect(cancelPath, '/api/services/10/cancel');
    expect(find.text('Solicitud cancelada'), findsWidgets);
  });

  testWidgets('servicio completado ofrece calificar: navega, POSTea el review y '
      'oculta la acción tras calificar', (tester) async {
    String? reviewPath;
    Map<String, dynamic>? reviewPayload;
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/10/review/') {
          reviewPath = request.url.path;
          reviewPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'message': 'Calificación registrada, ¡gracias!',
              'review_id': 1,
              'global_score': 4.7,
              'technician_rating': 4.7,
            }),
            201,
          );
        }
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [
                _summaryJson(
                  id: 10,
                  status: 'completed',
                  technicianName: 'Carlos Tecnico',
                ),
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(_detailJson(id: 10, status: 'completed')),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    // Acción de calificación solo en estado completado (RF-RAT-007).
    expect(find.text('Calificar servicio'), findsOneWidget);
    await tester.tap(find.text('Calificar servicio'));
    await tester.pumpAndSettle();

    // Pantalla de rating con las 3 sub-dimensiones accesible desde el historial.
    expect(find.text('Puntualidad'), findsOneWidget);
    expect(find.text('Calidad'), findsOneWidget);
    expect(find.text('Profesionalismo'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('comentario')),
      'Excelente servicio, muy puntual',
    );
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();

    expect(reviewPath, '/api/services/10/review/');
    expect(reviewPayload!['punctuality'], 5);
    expect(reviewPayload!['quality'], 5);
    expect(reviewPayload!['professionalism'], 5);
    expect(reviewPayload!['comment'], 'Excelente servicio, muy puntual');
    // Agradecimiento + la acción desaparece (ya calificado en esta sesión).
    expect(find.textContaining('Calificación registrada'), findsWidgets);
    expect(find.text('Calificar servicio'), findsNothing);
  });

  testWidgets('servicio sin completar NO ofrece calificar', (tester) async {
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'in_progress')],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(_detailJson(id: 10, status: 'in_progress')),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    expect(find.text('Calificar servicio'), findsNothing);
  });

  testWidgets('tracking solo aparece para servicio en proceso asignado', (
    tester,
  ) async {
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'in_progress')],
            }),
            200,
          );
        }
        if (request.url.path == '/api/services/10') {
          final detail = _detailJson(id: 10, status: 'in_progress');
          detail['latitude'] = 7.8939;
          detail['longitude'] = -72.5078;
          return http.Response(jsonEncode(detail), 200);
        }
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();

    expect(find.text('Ver ubicación del técnico'), findsOneWidget);
    await tester.tap(find.text('Ver ubicación del técnico'));
    await tester.pumpAndSettle();
    expect(find.text('Rastreo del Técnico'), findsOneWidget);
  });

  testWidgets('muestra error visible cuando falla una acción de oferta', (
    tester,
  ) async {
    ApiClient.setClient(
      FakeClient((request) {
        if (request.url.path == '/api/services/my') {
          return http.Response(
            jsonEncode({
              'requests': [_summaryJson(id: 10, status: 'bidding')],
            }),
            200,
          );
        }
        if (request.url.path == '/api/services/10/bids/3/accept') {
          return http.Response(jsonEncode({'detail': 'falló'}), 500);
        }
        return http.Response(
          jsonEncode(
            _detailJson(id: 10, status: 'bidding', bidStatus: 'pending'),
          ),
          200,
        );
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: ClientHistoryScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nevera clásica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar oferta'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo aceptar la oferta. Reintenta.'),
      findsOneWidget,
    );
  });
}
