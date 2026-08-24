import 'package:flutter_test/flutter_test.dart';
import 'package:cold_day_flutter/core/network/api_client.dart';

void main() {
  test('403 explains verification and login action', () {
    expect(
      ApiClient.userFacingError(
        Exception('Error (403): forbidden'),
        action: 'cargar el radar',
      ),
      contains('cuenta de técnico esté verificada'),
    );
  });

  test('network errors suggest retry without presenting them as 403', () {
    expect(
      ApiClient.userFacingError(
        Exception('TimeoutException'),
        action: 'cargar el radar',
      ),
      contains('conexión'),
    );
  });
}
