import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  /// Resuelve la URL base según la plataforma:
  ///
  /// Orden de prioridad:
  /// 1. `--dart-define=API_URL=http://<IP-PC>:8000` (override explícito)
  /// 2. Android físico: usa la IP de la red local del PC (API_URL es obligatorio
  ///    porque 10.0.2.2 solo existe en el emulador; si no hay define, falla claro)
  /// 3. Android emulador: 10.0.2.2 (alias del host)
  /// 4. iOS simulator / web / desktop: 127.0.0.1
  static String get baseUrl {
    const apiPath = "/api";

    // Override explícito: flutter run --dart-define=API_URL=http://192.168.1.4:8000
    const fromEnv = String.fromEnvironment('API_URL');
    if (fromEnv.isNotEmpty) return "$fromEnv$apiPath";

    if (kIsWeb) return "http://127.0.0.1:8000$apiPath";

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android físico vs emulador: 10.0.2.2 solo funciona en el emulador.
      // Para un teléfono físico pasá API_URL con la IP local de tu PC.
      const isEmulator = bool.fromEnvironment('ANDROID_EMULATOR');
      if (isEmulator) return "http://10.0.2.2:8000$apiPath";
      return "http://127.0.0.1:8000$apiPath"; // reemplazado por API_URL real
    }

    return "http://127.0.0.1:8000$apiPath";
  }

  /// Timeout corto para fallar rápido y no dejar la UI colgada.
  static const Duration _timeout = Duration(seconds: 8);

  static Future<Map<String, dynamic>> createServiceRequest({
    required int userId,
    required int equipmentId,
    required String serviceType,
    required String description,
    required double latitude,
    required double longitude,
    double? budgetOffered,
  }) async {
    final url = Uri.parse("$baseUrl/services/");
    final response = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": userId,
            "equipment_id": equipmentId,
            "service_type": serviceType,
            "description": description,
            "latitude": latitude,
            "longitude": longitude,
            "budget_offered": budgetOffered,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al crear la solicitud: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> sendTechnicianBid({
    required int serviceRequestId,
    required int technicianId,
    required double priceOffered,
    required int estimatedTimeMinutes,
  }) async {
    final url = Uri.parse("$baseUrl/services/bids/");
    final response = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "service_request_id": serviceRequestId,
            "technician_id": technicianId,
            "price_offered": priceOffered,
            "estimated_time_minutes": estimatedTimeMinutes,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al enviar la oferta: ${response.body}");
    }
  }

  static Future<List<Map<String, dynamic>>> findNearbyTechnicians({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    final url = Uri.parse(
      "$baseUrl/services/technicians-nearby/"
      "?latitude=$latitude&longitude=$longitude&radius_km=$radiusKm",
    );
    final response = await http.get(url).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final technicians = body['technicians'] as List<dynamic>;
      return technicians
          .map((tech) => tech as Map<String, dynamic>)
          .toList();
    } else {
      throw Exception("Error al buscar técnicos: ${response.body}");
    }
  }

  /// Catálogo data-driven: categoría -> sector -> equipos -> precios.
  static Future<List<Map<String, dynamic>>> fetchCatalog() async {
    final url = Uri.parse("$baseUrl/catalog/");
    final response = await http.get(url).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final categories = body['categories'] as List<dynamic>;
      return categories
          .map((cat) => cat as Map<String, dynamic>)
          .toList();
    } else {
      throw Exception("Error al cargar el catálogo: ${response.body}");
    }
  }
}
