import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cold_day_flutter/core/network/token_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('store vacío no tiene sesión y lee null', () async {
    expect(await TokenStore.hasSession(), isFalse);
    expect(await TokenStore.readAccessToken(), isNull);
    expect(await TokenStore.readRefreshToken(), isNull);
    expect(await TokenStore.readRole(), isNull);
    expect(await TokenStore.readUserId(), isNull);
  });

  test('save persiste el par de tokens y la sesión; clear la elimina',
      () async {
    await TokenStore.save(
      accessToken: 'access-abc',
      refreshToken: 'refresh-xyz',
      role: 'client',
      userId: 7,
    );

    expect(await TokenStore.readAccessToken(), 'access-abc');
    expect(await TokenStore.readRefreshToken(), 'refresh-xyz');
    expect(await TokenStore.readRole(), 'client');
    expect(await TokenStore.readUserId(), 7);
    expect(await TokenStore.hasSession(), isTrue);

    await TokenStore.clear();

    expect(await TokenStore.hasSession(), isFalse);
    expect(await TokenStore.readAccessToken(), isNull);
    expect(await TokenStore.readRole(), isNull);
  });
}