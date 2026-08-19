// Persistencia del par de tokens (access + refresh) y datos de sesión.
//
// Piloto: usa `shared_preferences` (NFR de la spec permite shared_preferences
// como almacenamiento de tokens para el piloto; flutter_secure_storage queda
// como upgrade de hardening post-piloto). Lecuras sin sesión devuelven null.
import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static const _accessKey = 'auth.access_token';
  static const _refreshKey = 'auth.refresh_token';
  static const _roleKey = 'auth.role';
  static const _userIdKey = 'auth.user_id';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String role,
    required int userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, accessToken);
    await prefs.setString(_refreshKey, refreshToken);
    await prefs.setString(_roleKey, role);
    await prefs.setInt(_userIdKey, userId);
  }

  static Future<String?> readAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessKey);
  }

  static Future<String?> readRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshKey);
  }

  static Future<String?> readRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  static Future<int?> readUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<bool> hasSession() async {
    return await readAccessToken() != null && await readRole() != null;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_userIdKey);
  }
}