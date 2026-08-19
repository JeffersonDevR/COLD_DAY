// Pantalla de calificación post-servicio (RF-RAT-007, HU-RAT-001): 3
// sub-dimensiones 1-5 (puntualidad, calidad, profesionalismo) + comentario
// opcional <= 1000, enviadas por el cliente dueño tras la finalización a
// POST /api/services/{id}/review/ (RF-RAT-001..003).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/ratings/rating_screen.dart';

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
      'auth.access_token': 'tok-client',
      'auth.refresh_token': 'refresh-client',
      'auth.role': 'client',
      'auth.user_id': 1,
    });
  });

  testWidgets('renderiza 3 sub-dimensiones, comentario y botón de envío',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(jsonEncode({'message': 'ok'}), 201);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: RatingScreen(requestId: 10)),
    );

    expect(find.text('Calificar servicio'), findsOneWidget);
    expect(find.text('Puntualidad'), findsOneWidget);
    expect(find.text('Calidad'), findsOneWidget);
    expect(find.text('Profesionalismo'), findsOneWidget);
    expect(find.byKey(const Key('comentario')), findsOneWidget);
    expect(find.text('Enviar calificación'), findsOneWidget);
  });

  testWidgets(
      'envía las 3 dims (con estrella ajustada) y el comentario con Bearer, '
      'y cierra con éxito', (tester) async {
    String? reviewPath;
    String? authorization;
    Map<String, dynamic>? payload;
    bool popped = false;
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/services/10/review/') {
        reviewPath = request.url.path;
        authorization = request.headers['Authorization'];
        payload = jsonDecode(request.body) as Map<String, dynamic>;
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
      return http.Response(jsonEncode({}), 404);
    }));

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const RatingScreen(requestId: 10, technicianName: 'Carlos Tecnico'),
              ),
            );
            popped = result == true;
          },
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Técnico visible + ajuste de la dimensión "Calidad" de 5 a 4 (estrella 4).
    expect(find.textContaining('Carlos Tecnico'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calidad-4')));
    await tester.enterText(
      find.byKey(const Key('comentario')),
      'Excelente servicio, muy puntual',
    );
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();

    expect(reviewPath, '/api/services/10/review/');
    expect(authorization, 'Bearer tok-client');
    expect(payload!['punctuality'], 5);
    expect(payload!['quality'], 4);
    expect(payload!['professionalism'], 5);
    expect(payload!['comment'], 'Excelente servicio, muy puntual');
    expect(popped, isTrue);
  });

  testWidgets('el comentario es opcional: envía sin comentario', (tester) async {
    Map<String, dynamic>? payload;
    ApiClient.setClient(FakeClient((request) {
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'message': 'Calificación registrada, ¡gracias!'}),
        201,
      );
    }));

    await tester.pumpWidget(
      const MaterialApp(home: RatingScreen(requestId: 10)),
    );
    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();

    expect(payload!['comment'], isNull);
    expect(payload!['punctuality'], 5);
  });

  testWidgets('error del backend (409 ya calificado) muestra mensaje y no cierra',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      return http.Response(
        jsonEncode({'detail': 'Este servicio ya fue calificado'}),
        409,
      );
    }));

    await tester.pumpWidget(
      const MaterialApp(home: RatingScreen(requestId: 10)),
    );

    await tester.tap(find.text('Enviar calificación'));
    await tester.pumpAndSettle();

    // Permanece en la pantalla y muestra el error del servidor (409).
    expect(find.text('Enviar calificación'), findsOneWidget);
    expect(find.textContaining('409'), findsOneWidget);
  });
}