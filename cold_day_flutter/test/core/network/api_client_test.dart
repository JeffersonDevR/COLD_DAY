import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/core/network/token_store.dart';

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
  group('ApiClient', () {
    // RF-MATCH-006: el radar técnico pega al endpoint REAL
    // /api/services/technicians-nearby/ (objeto {count, technicians}).
    test(
      'fetchNearbyRequests hits /api/services/technicians-nearby/',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/services/technicians-nearby/');
            expect(request.url.queryParameters['latitude'], '7.8939');
            expect(request.url.queryParameters['longitude'], '-72.5078');
            return http.Response(
              jsonEncode({
                'count': 1,
                'radius_km': 5.0,
                'technicians': [
                  {
                    'id': 7,
                    'name': 'Carlos Tecnico',
                    'rating': 4.5,
                    'specialty': 'Neveras',
                    'distance_km': 1.2,
                  },
                ],
              }),
              200,
            );
          }),
        );

        final technicians = await ApiClient.fetchNearbyRequests(
          latitude: 7.8939,
          longitude: -72.5078,
        );
        expect(technicians, isA<List<Map<String, dynamic>>>());
        expect(technicians, hasLength(1));
        expect(technicians[0]['id'], 7);
        expect(technicians[0]['distance_km'], 1.2);
      },
    );

    test(
      'fetchNearbyRequests returns empty list when area has no technicians',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            return http.Response(
              jsonEncode({'count': 0, 'technicians': []}),
              200,
            );
          }),
        );

        final technicians = await ApiClient.fetchNearbyRequests(
          latitude: 0.0,
          longitude: 0.0,
        );
        expect(technicians, isEmpty);
      },
    );
  });

  group('ApiClient auth (RF-AUTH-001..007)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('login POSTea document+password a /api/auth/login', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/auth/login');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['document'], '1123456789');
          expect(body['password'], 'Secreto1');
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'role': 'client',
              'user_id': 1,
            }),
            200,
          );
        }),
      );

      final result = await ApiClient.login(
        document: '1123456789',
        password: 'Secreto1',
      );
      expect(result['role'], 'client');
      expect(result['access_token'], 'access-1');
    });

    test('login con 401 lanza excepción', () async {
      ApiClient.setClient(
        FakeClient((request) {
          return http.Response(
            jsonEncode({'detail': 'Credenciales inválidas'}),
            401,
          );
        }),
      );

      expect(
        () => ApiClient.login(document: 'x', password: 'y'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'registerClient POSTea el payload completo a /api/auth/register/client',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.url.path, '/api/auth/register/client');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['full_name'], 'Ana Pérez');
            expect(body['document'], '1123456789');
            expect(body['phone'], '3001234567');
            expect(body['password'], 'ClaveSegura1');
            return http.Response(
              jsonEncode({
                'id': 3,
                'full_name': 'Ana Pérez',
                'document': '1123456789',
                'phone': '3001234567',
                'role': 'client',
              }),
              201,
            );
          }),
        );

        final result = await ApiClient.registerClient(
          fullName: 'Ana Pérez',
          document: '1123456789',
          phone: '3001234567',
          password: 'ClaveSegura1',
        );
        expect(result['id'], 3);
        expect(result['role'], 'client');
      },
    );

    test('registerTechnician envía specialty y lat/lng', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.url.path, '/api/auth/register/technician');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['specialty'], 'Aires acondicionados');
          expect(body['latitude'], 7.8939);
          expect(body['longitude'], -72.5078);
          return http.Response(
            jsonEncode({
              'id': 4,
              'full_name': 'Luis Díaz',
              'document': '1098765432',
              'phone': '3012345678',
              'role': 'technician',
            }),
            201,
          );
        }),
      );

      final result = await ApiClient.registerTechnician(
        fullName: 'Luis Díaz',
        document: '1098765432',
        phone: '3012345678',
        password: 'TecnicoSeg1',
        specialty: 'Aires acondicionados',
        latitude: 7.8939,
        longitude: -72.5078,
      );
      expect(result['role'], 'technician');
    });

    test('refresh envía el refresh token y devuelve el par nuevo', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.url.path, '/api/auth/refresh');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refresh_token'], 'refresh-old');
          return http.Response(
            jsonEncode({
              'access_token': 'access-new',
              'refresh_token': 'refresh-new',
              'role': 'client',
              'user_id': 1,
            }),
            200,
          );
        }),
      );

      final result = await ApiClient.refresh('refresh-old');
      expect(result['access_token'], 'access-new');
    });

    test('logout envía el refresh token a /api/auth/logout', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.url.path, '/api/auth/logout');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refresh_token'], 'refresh-1');
          return http.Response(jsonEncode({'message': 'Sesión cerrada'}), 200);
        }),
      );

      await ApiClient.logout('refresh-1');
    });

    test(
      'me() envía el header Authorization Bearer con el token guardado',
      () async {
        await TokenStore.save(
          accessToken: 'tok-abc',
          refreshToken: 'refresh-1',
          role: 'client',
          userId: 1,
        );
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.url.path, '/api/auth/me');
            expect(request.headers['Authorization'], 'Bearer tok-abc');
            return http.Response(
              jsonEncode({
                'id': 1,
                'full_name': 'Ana Pérez',
                'document': '1123456789',
                'phone': '3001234567',
                'role': 'client',
              }),
              200,
            );
          }),
        );

        final me = await ApiClient.me();
        expect(me['full_name'], 'Ana Pérez');
        expect(me['role'], 'client');
      },
    );

    test('me() sin sesión activa lanza', () async {
      ApiClient.setClient(
        FakeClient((request) {
          return http.Response('{}', 200);
        }),
      );

      expect(() => ApiClient.me(), throwsA(isA<Exception>()));
    });
  });

  group('ApiClient S2 contract fixes (RF-SR-001/002, RF-MATCH-006)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'createServiceRequest envía Bearer y NO incluye user_id en el payload',
      () async {
        await TokenStore.save(
          accessToken: 'tok-s2',
          refreshToken: 'refresh-s2',
          role: 'client',
          userId: 1,
        );
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/services/');
            expect(request.headers['Authorization'], 'Bearer tok-s2');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body.containsKey('user_id'), isFalse);
            expect(body['equipment_id'], null);
            expect(body['service_type'], 'repair');
            expect(body['description'], 'No enfría');
            expect(body['latitude'], 7.8939);
            expect(body['category_hint'], 'Neveras');
            return http.Response(
              jsonEncode({
                'message': 'ok',
                'request_id': 42,
                'status': 'requested',
              }),
              201,
            );
          }),
        );

        final result = await ApiClient.createServiceRequest(
          serviceType: 'repair',
          description: 'No enfría',
          latitude: 7.8939,
          longitude: -72.5078,
          categoryHint: 'Neveras',
        );
        expect(result['request_id'], 42);
      },
    );

    test('createServiceRequest sin sesión activa lanza', () async {
      ApiClient.setClient(
        FakeClient((request) {
          return http.Response('{}', 201);
        }),
      );

      expect(
        () => ApiClient.createServiceRequest(
          serviceType: 'repair',
          description: 'x',
          latitude: 7.0,
          longitude: -72.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('sendTechnicianBid envía costos, Bearer y NO technician_id', () async {
      await TokenStore.save(
        accessToken: 'tok-s2',
        refreshToken: 'refresh-s2',
        role: 'technician',
        userId: 2,
      );
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/services/bids/');
          expect(request.headers['Authorization'], 'Bearer tok-s2');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['service_request_id'], 42);
          expect(body['transport_cost'], 15000);
          expect(body['diagnosis_cost'], 35000);
          expect(body.containsKey('technician_id'), isFalse);
          return http.Response(
            jsonEncode({'message': 'ok', 'bid_id': 9, 'status': 'pending'}),
            201,
          );
        }),
      );

      final result = await ApiClient.sendTechnicianBid(
        serviceRequestId: 42,
        priceOffered: 50000,
        estimatedTimeMinutes: 45,
        transportCost: 15000,
        diagnosisCost: 35000,
      );
      expect(result['bid_id'], 9);
    });
  });

  group('ApiClient S3 técnico (RF-MATCH-004, RF-SR-004/005/008)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access_token': 'tok-s3',
        'auth.refresh_token': 'refresh-s3',
        'auth.role': 'technician',
        'auth.user_id': 2,
      });
    });

    test(
      'fetchTechnicianRadar GETea el radar real con Bearer y radius_km',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/technicians/requests/nearby/');
            expect(request.headers['Authorization'], 'Bearer tok-s3');
            expect(request.url.queryParameters['radius_km'], '10.0');
            return http.Response(
              jsonEncode({
                'requests': [
                  {
                    'id': 10,
                    'equipment': 'Nevera clásica',
                    'description': 'No enfría',
                    'latitude': 7.8939,
                    'longitude': -72.5078,
                    'status': 'requested',
                    'my_bid_status': null,
                  },
                ],
              }),
              200,
            );
          }),
        );

        final requests = await ApiClient.fetchTechnicianRadar();
        expect(requests, hasLength(1));
        expect(requests[0]['id'], 10);
        expect(requests[0]['status'], 'requested');
      },
    );

    test(
      'registerDiagnosis POSTea observations a /services/{id}/diagnosis',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/services/12/diagnosis');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['observations'], 'Fuga de gas refrigerante');
            return http.Response(
              jsonEncode({
                'message': 'Diagnóstico registrado',
                'request_id': 12,
                'status': 'diagnosis',
              }),
              200,
            );
          }),
        );

        final result = await ApiClient.registerDiagnosis(
          requestId: 12,
          observations: 'Fuga de gas refrigerante',
        );
        expect(result['status'], 'diagnosis');
      },
    );

    test(
      'proposeAgreement POSTea el desglose a /services/{id}/agreements/',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/services/12/agreements/');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['labor_cost'], 80000);
            expect(body['transport_cost'], 15000);
            expect(body['diagnosis_cost'], 35000);
            expect(body['observations'], 'Fuga de gas');
            return http.Response(
              jsonEncode({
                'message': 'Pacto de servicio propuesto al cliente',
                'agreement_id': 5,
                'request_id': 12,
                'total': 130000,
                'status': 'proposed',
              }),
              201,
            );
          }),
        );

        final result = await ApiClient.proposeAgreement(
          requestId: 12,
          laborCost: 80000,
          transportCost: 15000,
          diagnosisCost: 35000,
          observations: 'Fuga de gas',
        );
        expect(result['total'], 130000);
      },
    );

    test('completeServiceRequest POSTea a /services/{id}/complete', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/services/12/complete');
          return http.Response(
            jsonEncode({
              'message': 'Servicio completado',
              'request_id': 12,
              'status': 'completed',
            }),
            200,
          );
        }),
      );

      final result = await ApiClient.completeServiceRequest(requestId: 12);
      expect(result['status'], 'completed');
    });
  });

  group('ApiClient S3 cliente (RF-SR-003/006/007/009/010)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access_token': 'tok-cli',
        'auth.refresh_token': 'refresh-cli',
        'auth.role': 'client',
        'auth.user_id': 1,
      });
    });

    test('fetchMyRequests GETea /api/services/my con Bearer', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/services/my');
          expect(request.headers['Authorization'], 'Bearer tok-cli');
          return http.Response(
            jsonEncode({
              'requests': [
                {'id': 10, 'status': 'bidding', 'equipment': 'Nevera clásica'},
              ],
            }),
            200,
          );
        }),
      );

      final requests = await ApiClient.fetchMyRequests();
      expect(requests, hasLength(1));
      expect(requests[0]['id'], 10);
    });

    test('fetchServiceRequestDetail GETea /api/services/{id}', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/services/10');
          return http.Response(
            jsonEncode({
              'id': 10,
              'status': 'pact_proposed',
              'timeline': {'bids': [], 'agreements': []},
            }),
            200,
          );
        }),
      );

      final detail = await ApiClient.fetchServiceRequestDetail(10);
      expect(detail['status'], 'pact_proposed');
      expect(detail['timeline'], isNotNull);
    });

    test('acceptBid POSTea a /services/{id}/bids/{bidId}/accept', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/services/10/bids/3/accept');
          return http.Response(
            jsonEncode({
              'message': 'Oferta aceptada',
              'request_id': 10,
              'status': 'diagnosis',
            }),
            200,
          );
        }),
      );

      final result = await ApiClient.acceptBid(requestId: 10, bidId: 3);
      expect(result['status'], 'diagnosis');
    });

    test(
      'acceptAgreement POSTea a /services/{id}/agreements/{agId}/accept',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/services/10/agreements/5/accept');
            return http.Response(
              jsonEncode({
                'message': 'Pacto aceptado',
                'request_id': 10,
                'status': 'in_progress',
              }),
              200,
            );
          }),
        );

        final result = await ApiClient.acceptAgreement(
          requestId: 10,
          agreementId: 5,
        );
        expect(result['status'], 'in_progress');
      },
    );

    test(
      'rejectAgreement POSTea a /services/{id}/agreements/{agId}/reject',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/services/10/agreements/5/reject');
            return http.Response(
              jsonEncode({
                'message': 'Pacto rechazado',
                'request_id': 10,
                'status': 'bidding',
              }),
              200,
            );
          }),
        );

        final result = await ApiClient.rejectAgreement(
          requestId: 10,
          agreementId: 5,
        );
        expect(result['status'], 'bidding');
      },
    );

    test('cancelServiceRequest POSTea a /services/{id}/cancel', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/services/10/cancel');
          return http.Response(
            jsonEncode({
              'message': 'Solicitud cancelada',
              'request_id': 10,
              'status': 'cancelled',
            }),
            200,
          );
        }),
      );

      final result = await ApiClient.cancelServiceRequest(requestId: 10);
      expect(result['status'], 'cancelled');
    });
  });

  group('ApiClient S4 ratings (RF-RAT-001..006)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access_token': 'tok-client',
        'auth.refresh_token': 'refresh-client',
        'auth.role': 'client',
        'auth.user_id': 1,
      });
    });

    test(
      'submitReview POSTea 3 dims + comentario a /services/{id}/review/',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/services/10/review/');
            expect(request.headers['Authorization'], 'Bearer tok-client');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['punctuality'], 5);
            expect(body['quality'], 4);
            expect(body['professionalism'], 5);
            expect(body['comment'], 'Excelente servicio, muy puntual');
            return http.Response(
              jsonEncode({
                'message': 'Calificación registrada, ¡gracias!',
                'review_id': 1,
                'global_score': 4.7,
                'technician_rating': 4.7,
              }),
              201,
            );
          }),
        );

        final result = await ApiClient.submitReview(
          requestId: 10,
          punctuality: 5,
          quality: 4,
          professionalism: 5,
          comment: 'Excelente servicio, muy puntual',
        );
        expect(result['global_score'], 4.7);
        expect(result['technician_rating'], 4.7);
      },
    );

    test('submitReview permite comentario opcional (null)', () async {
      ApiClient.setClient(
        FakeClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['comment'], isNull);
          expect(body['punctuality'], 5);
          return http.Response(
            jsonEncode({'message': 'Calificación registrada, ¡gracias!'}),
            201,
          );
        }),
      );

      final result = await ApiClient.submitReview(
        requestId: 10,
        punctuality: 5,
        quality: 5,
        professionalism: 5,
      );
      expect(result['message'], 'Calificación registrada, ¡gracias!');
    });
  });

  group('ApiClient S5 admin (RF-ADM-001..008)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access_token': 'tok-admin',
        'auth.refresh_token': 'refresh-admin',
        'auth.role': 'admin',
        'auth.user_id': 9,
      });
    });

    test('fetchAdminKpis GETea /api/admin/kpis con Bearer', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/admin/kpis');
          expect(request.headers['Authorization'], 'Bearer tok-admin');
          return http.Response(
            jsonEncode({
              'total_clients': 5,
              'total_technicians': 6,
              'pending_technicians': 2,
              'requests_by_status': {'requested': 4, 'bidding': 3},
            }),
            200,
          );
        }),
      );

      final kpis = await ApiClient.fetchAdminKpis();
      expect(kpis['total_clients'], 5);
      expect(kpis['pending_technicians'], 2);
      expect(kpis['requests_by_status']['bidding'], 3);
    });

    test('fetchAdminTechnicians GETea /api/admin/users/technicians', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/admin/users/technicians');
          return http.Response(
            jsonEncode({
              'technicians': [
                {
                  'id': 3,
                  'name': 'Carlos Tecnico',
                  'specialty': 'Neveras',
                  'verification_status': 'pending',
                  'rating': 0.0,
                },
              ],
            }),
            200,
          );
        }),
      );

      final technicians = await ApiClient.fetchAdminTechnicians();
      expect(technicians, hasLength(1));
      expect(technicians[0]['id'], 3);
      expect(technicians[0]['verification_status'], 'pending');
    });

    test(
      'verifyTechnician POSTea a /technicians/{id}/verify con Bearer',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/admin/technicians/3/verify');
            expect(request.headers['Authorization'], 'Bearer tok-admin');
            return http.Response(
              jsonEncode({
                'message': 'Técnico verificado',
                'technician_id': 3,
                'verification_status': 'verified',
              }),
              200,
            );
          }),
        );

        final result = await ApiClient.verifyTechnician(3);
        expect(result['verification_status'], 'verified');
      },
    );

    test(
      'rejectTechnician POSTea el motivo a /technicians/{id}/reject',
      () async {
        ApiClient.setClient(
          FakeClient((request) {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/admin/technicians/3/reject');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['reason'], 'Documentación incompleta');
            return http.Response(
              jsonEncode({
                'message': 'Técnico rechazado',
                'technician_id': 3,
                'verification_status': 'rejected',
              }),
              200,
            );
          }),
        );

        final result = await ApiClient.rejectTechnician(
          3,
          'Documentación incompleta',
        );
        expect(result['verification_status'], 'rejected');
      },
    );
  });

  group('ApiClient technician services contract', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access_token': 'tok-tech',
        'auth.role': 'technician',
      });
    });

    test('fetchMyServices accepts the backend bare list response', () async {
      ApiClient.setClient(
        FakeClient((request) {
          expect(request.url.path, '/api/technicians/me/services');
          return http.Response(
            jsonEncode([
              {
                'id': 4,
                'category_id': 2,
                'service_types': ['repair'],
                'sector': 'residential',
                'active': true,
              },
            ]),
            200,
          );
        }),
      );

      final services = await ApiClient.fetchMyServices();
      expect(services, hasLength(1));
      expect(services.single['id'], 4);
    });
  });
}
