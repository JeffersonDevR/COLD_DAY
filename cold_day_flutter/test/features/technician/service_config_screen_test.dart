import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/technician/service_config_screen.dart';

class _Client extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path == '/api/catalog/'
        ? {
            'categories': [
              {'id': 3, 'name': 'Aire acondicionado'},
            ],
          }
        : {
            'services': [
              {
                'id': 9,
                'category_id': 3,
                'category_name': 'Aire acondicionado',
                'service_types': ['repair', 'maintenance'],
                'sector': 'both',
                'active': true,
              },
            ],
          };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
    );
  }
}

void main() {
  testWidgets('renders the backend service contract as readable chips', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'auth.access_token': 'tok-tech'});
    ApiClient.setClient(_Client());
    await tester.pumpWidget(const MaterialApp(home: ServiceConfigScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Aire acondicionado'), findsOneWidget);
    expect(find.text('Reparación'), findsOneWidget);
    expect(find.text('Mantenimiento'), findsOneWidget);
    expect(find.textContaining('Ambos'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
  });
}
