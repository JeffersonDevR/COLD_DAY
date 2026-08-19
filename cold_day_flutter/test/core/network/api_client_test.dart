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
    test('fetchNearbyRequests returns a list of requests', () async {
      ApiClient.setClient(FakeClient((request) {
        return http.Response(jsonEncode([]), 200);
      }));
      
      final requests = await ApiClient.fetchNearbyRequests(latitude: 0.0, longitude: 0.0);
      expect(requests, isA<List<Map<String, dynamic>>>());
      expect(requests, isEmpty);
    });

    test('fetchNearbyRequests returns non-empty list when data exists', () async {
      ApiClient.setClient(FakeClient((request) {
        return http.Response(jsonEncode([{'id': 1}]), 200);
      }));
      
      final requests = await ApiClient.fetchNearbyRequests(latitude: 0.0, longitude: 0.0);
      expect(requests.length, greaterThan(0));
      expect(requests[0]['id'], 1);
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
}
