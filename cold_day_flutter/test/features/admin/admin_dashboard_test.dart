// Task 5.3 — RED: dashboard admin (HU-ADM-001/002, RF-ADM-001..008).
//
// KPIs del piloto (clientes/técnicos/pendientes + desglose por estado) y cola
// de verificación con aprobar/rechazar (motivo obligatorio). Referencia
// `features/admin/admin_dashboard_screen.dart` y los métodos admin de
// `ApiClient`, que no existen todavía -> RED garantizado (compile fail).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/admin/admin_dashboard_screen.dart';
import 'package:cold_day_flutter/features/auth/auth_router.dart';

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

Map<String, dynamic> _kpisBody() => {
      'total_clients': 5,
      'total_technicians': 6,
      'pending_technicians': 2,
      'requests_by_status': {
        'requested': 4,
        'bidding': 3,
        'diagnosis': 0,
        'pact_proposed': 0,
        'in_progress': 2,
        'completed': 1,
        'cancelled': 0,
      },
    };

Map<String, dynamic> _techBody() => {
      'technicians': [
        {
          'id': 1,
          'name': 'Carlos Tecnico',
          'specialty': 'Neveras',
          'verification_status': 'pending',
          'rating': 0.0,
        },
        {
          'id': 2,
          'name': 'Lucía Reparadora',
          'specialty': 'Aire acondicionado',
          'verification_status': 'pending',
          'rating': 0.0,
        },
        {
          'id': 3,
          'name': 'Pedro Verificado',
          'specialty': 'Lavadoras',
          'verification_status': 'verified',
          'rating': 4.5,
        },
      ],
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'tok-admin',
      'auth.refresh_token': 'refresh-admin',
      'auth.role': 'admin',
      'auth.user_id': 9,
    });
  });

  testWidgets('renderiza KPIs (totales + desglose por estado)',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/admin/kpis') {
        return http.Response(jsonEncode(_kpisBody()), 200);
      }
      if (request.url.path == '/api/admin/users/technicians') {
        return http.Response(jsonEncode(_techBody()), 200);
      }
      return http.Response(jsonEncode({}), 404);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardScreen()),
    );
    await tester.pumpAndSettle();

    // Totales del piloto (RF-ADM-002).
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-clients'))).data,
      '5',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-technicians'))).data,
      '6',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-pending'))).data,
      '2',
    );
    // Desglose de solicitudes por estado (labels en español, spec §6).
    expect(find.text('Pendiente (4)'), findsOneWidget);
    expect(find.text('En oferta (3)'), findsOneWidget);
    expect(find.text('En proceso (2)'), findsOneWidget);
    expect(find.text('Completada (1)'), findsOneWidget);
  });

  testWidgets('cola de verificación muestra solo pendientes con acciones',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/admin/kpis') {
        return http.Response(jsonEncode(_kpisBody()), 200);
      }
      if (request.url.path == '/api/admin/users/technicians') {
        return http.Response(jsonEncode(_techBody()), 200);
      }
      return http.Response(jsonEncode({}), 404);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardScreen()),
    );
    await tester.pumpAndSettle();

    // Los 2 pendientes están en la cola con ambas acciones (RF-ADM-005).
    expect(find.text('Carlos Tecnico'), findsOneWidget);
    expect(find.text('Lucía Reparadora'), findsOneWidget);
    expect(find.text('Aprobar'), findsNWidgets(2));
    expect(find.text('Rechazar'), findsNWidgets(2));
    // Un técnico verificado NO cae en la cola: se muestra en "Todos los
    // técnicos" (sección posterior del ListView, requiere scroll).
    await tester.scrollUntilVisible(find.text('Pedro Verificado'), 300);
    expect(find.text('Pedro Verificado'), findsOneWidget);
    expect(find.text('Verificado'), findsWidgets);
  });

  testWidgets('aprobar verifica al técnico (POST Bearer) y recarga la cola',
      (tester) async {
    String? verifyPath;
    String? authorization;
    var kpisCalls = 0;
    var pendingNow = 2;
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/admin/technicians/1/verify') {
        verifyPath = request.url.path;
        authorization = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'message': 'Técnico verificado',
            'technician_id': 1,
            'verification_status': 'verified',
          }),
          200,
        );
      }
      if (request.url.path == '/api/admin/kpis') {
        kpisCalls++;
        final body = _kpisBody();
        if (kpisCalls > 1) body['pending_technicians'] = --pendingNow;
        return http.Response(jsonEncode(body), 200);
      }
      if (request.url.path == '/api/admin/users/technicians') {
        final body = _techBody();
        if (kpisCalls > 1) {
          (body['technicians'] as List)[0]['verification_status'] = 'verified';
        }
        return http.Response(jsonEncode(body), 200);
      }
      return http.Response(jsonEncode({}), 404);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar').first);
    await tester.pumpAndSettle();

    expect(verifyPath, '/api/admin/technicians/1/verify');
    expect(authorization, 'Bearer tok-admin');
    // Tras recargar, la cola queda con 1 pendiente y el KPI baja a 1.
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-pending'))).data,
      '1',
    );
    expect(find.text('Aprobar'), findsOneWidget);
  });

  testWidgets('rechazar exige motivo: botón deshabilitado hasta escribirlo',
      (tester) async {
    String? rejectPath;
    Map<String, dynamic>? payload;
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path.endsWith('/reject')) {
        rejectPath = request.url.path;
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'message': 'Técnico rechazado',
            'technician_id': 1,
            'verification_status': 'rejected',
          }),
          200,
        );
      }
      if (request.url.path == '/api/admin/kpis') {
        return http.Response(jsonEncode(_kpisBody()), 200);
      }
      if (request.url.path == '/api/admin/users/technicians') {
        return http.Response(jsonEncode(_techBody()), 200);
      }
      return http.Response(jsonEncode({}), 404);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rechazar').first);
    await tester.pumpAndSettle();

    // Sin motivo el botón de confirmar está deshabilitado (RF-ADM-005 NFR).
    final confirmButton = find.widgetWithText(FilledButton, 'Rechazar técnico');
    expect(
      tester.widget<FilledButton>(confirmButton).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('reject-reason')),
      'Documentación incompleta',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(confirmButton).onPressed,
      isNotNull,
    );

    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(rejectPath, '/api/admin/technicians/1/reject');
    expect(payload!['reason'], 'Documentación incompleta');
    expect(find.textContaining('rechazado'), findsOneWidget);
  });

  testWidgets('error de carga muestra reintentar y recarga con éxito',
      (tester) async {
    var failing = true;
    ApiClient.setClient(FakeClient((request) {
      if (failing) {
        return http.Response(jsonEncode({'detail': 'boom'}), 500);
      }
      if (request.url.path == '/api/admin/kpis') {
        return http.Response(jsonEncode(_kpisBody()), 200);
      }
      if (request.url.path == '/api/admin/users/technicians') {
        return http.Response(jsonEncode(_techBody()), 200);
      }
      return http.Response(jsonEncode({}), 404);
    }));

    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);

    failing = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('kpi-clients'))).data,
      '5',
    );
  });

  testWidgets('routing por rol: admin abre el dashboard, no el placeholder',
      (tester) async {
    ApiClient.setClient(FakeClient((request) {
      if (request.url.path == '/api/admin/kpis') {
        return http.Response(jsonEncode(_kpisBody()), 200);
      }
      if (request.url.path == '/api/admin/users/technicians') {
        return http.Response(jsonEncode(_techBody()), 200);
      }
      return http.Response(jsonEncode({}), 404);
    }));
    await tester.pumpWidget(MaterialApp(home: roleHome('admin')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
    expect(find.text('Próximamente'), findsNothing);
  });
}