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
    test('fetchNearbyRequests hits /api/services/technicians-nearby/',
        () async {
      ApiClient.setClient(FakeClient((request) {
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
              }
            ],
          }),
          200,
        );
      }));

      final technicians = await ApiClient.fetchNearbyRequests(
        latitude: 7.8939,
        longitude: -72.5078,
      );
      expect(technicians, isA<List<Map<String, dynamic>>>());
      expect(technicians, hasLength(1));
      expect(technicians[0]['id'], 7);
      expect(technicians[0]['distance_km'], 1.2);
    });

    test('fetchNearbyRequests returns empty list when area has no technicians',
        () async {
      ApiClient.setClient(FakeClient((request) {
        return http.Response(
          jsonEncode({'count': 0, 'technicians': []}),
          200,
        );
      }));

      final technicians = await ApiClient.fetchNearbyRequests(
        latitude: 0.0,
        longitude: 0.0,
      );
      expect(technicians, isEmpty);
    });
  });

  group('ApiClient auth (RF-AUTH-001..007)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('login POSTea document+password a /api/auth/login', () async {
      ApiClient.setClient(FakeClient((request) {
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
      }));

      final result =
          await ApiClient.login(document: '1123456789', password: 'Secreto1');
      expect(result['role'], 'client');
      expect(result['access_token'], 'access-1');
    });

    test('login con 401 lanza excepción', () async {
      ApiClient.setClient(FakeClient((request) {
        return http.Response(jsonEncode({'detail': 'Credenciales inválidas'}), 401);
      }));

      expect(
        () => ApiClient.login(document: 'x', password: 'y'),
        throwsA(isA<Exception>()),
      );
    });

    test('registerClient POSTea el payload completo a /api/auth/register/client',
        () async {
      ApiClient.setClient(FakeClient((request) {
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
      }));

      final result = await ApiClient.registerClient(
        fullName: 'Ana Pérez',
        document: '1123456789',
        phone: '3001234567',
        password: 'ClaveSegura1',
      );
      expect(result['id'], 3);
      expect(result['role'], 'client');
    });

    test('registerTechnician envía specialty y lat/lng', () async {
      ApiClient.setClient(FakeClient((request) {
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
      }));

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
      ApiClient.setClient(FakeClient((request) {
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
      }));

      final result = await ApiClient.refresh('refresh-old');
      expect(result['access_token'], 'access-new');
    });

    test('logout envía el refresh token a /api/auth/logout', () async {
      ApiClient.setClient(FakeClient((request) {
        expect(request.url.path, '/api/auth/logout');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refresh_token'], 'refresh-1');
        return http.Response(jsonEncode({'message': 'Sesión cerrada'}), 200);
      }));

      await ApiClient.logout('refresh-1');
    });

    test('me() envía el header Authorization Bearer con el token guardado',
        () async {
      await TokenStore.save(
        accessToken: 'tok-abc',
        refreshToken: 'refresh-1',
        role: 'client',
        userId: 1,
      );
      ApiClient.setClient(FakeClient((request) {
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
      }));

      final me = await ApiClient.me();
      expect(me['full_name'], 'Ana Pérez');
      expect(me['role'], 'client');
    });

    test('me() sin sesión activa lanza', () async {
      ApiClient.setClient(FakeClient((request) {
        return http.Response('{}', 200);
      }));

      expect(() => ApiClient.me(), throwsA(isA<Exception>()));
    });
  });

  group('ApiClient S2 contract fixes (RF-SR-001/002, RF-MATCH-006)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('createServiceRequest envía Bearer y NO incluye user_id en el payload',
        () async {
      await TokenStore.save(
        accessToken: 'tok-s2',
        refreshToken: 'refresh-s2',
        role: 'client',
        userId: 1,
      );
      ApiClient.setClient(FakeClient((request) {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/services/');
        expect(request.headers['Authorization'], 'Bearer tok-s2');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('user_id'), isFalse);
        expect(body['equipment_id'], 5);
        expect(body['service_type'], 'repair');
        expect(body['description'], 'No enfría');
        expect(body['latitude'], 7.8939);
        return http.Response(
          jsonEncode({'message': 'ok', 'request_id': 42, 'status': 'requested'}),
          201,
        );
      }));

      final result = await ApiClient.createServiceRequest(
        equipmentId: 5,
        serviceType: 'repair',
        description: 'No enfría',
        latitude: 7.8939,
        longitude: -72.5078,
      );
      expect(result['request_id'], 42);
    });

    test('createServiceRequest sin sesión activa lanza', () async {
      ApiClient.setClient(FakeClient((request) {
        return http.Response('{}', 201);
      }));

      expect(
        () => ApiClient.createServiceRequest(
          equipmentId: 1,
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
      ApiClient.setClient(FakeClient((request) {
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
      }));

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
}
