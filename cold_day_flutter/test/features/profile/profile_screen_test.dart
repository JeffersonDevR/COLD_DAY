import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/api_client.dart';
import 'package:cold_day_flutter/features/profile/profile_screen.dart';

class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = http.Response(
      jsonEncode({
        'id': 1,
        'full_name': 'Ana Cliente',
        'document': '1123456789',
        'phone': '3001234567',
        'role': 'client',
      }),
      200,
    );
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  testWidgets('profile consumes flat UserOut response', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.access_token': 'profile-token',
      'auth.refresh_token': 'profile-refresh',
      'auth.role': 'client',
      'auth.user_id': 1,
    });
    ApiClient.setClient(_FakeClient());

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Ana Cliente'), findsOneWidget);
    expect(find.text('1123456789'), findsOneWidget);
    expect(find.text('3001234567'), findsOneWidget);
  });
}
