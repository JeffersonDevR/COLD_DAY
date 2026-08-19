import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:cold_day_flutter/core/network/token_store.dart';

class ApiClient {
  static http.Client _client = http.Client();

  @visibleForTesting
  static void setClient(http.Client client) => _client = client;

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

  static Future<Map<String, dynamic>> _decodeOrThrow(
    http.Response response,
    String message,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Future.value(
        response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
      "$message (${response.statusCode}): "
      "${response.body.isEmpty ? 'sin detalle' : response.body}",
    );
  }

  static Map<String, String> _jsonHeaders() =>
      {"Content-Type": "application/json"};

  /// Headers para endpoints autenticados: JSON + `Authorization: Bearer`.
  /// sin sesión activa lanza para que la UI no pegue sin token.
  static Future<Map<String, String>> _authedHeaders() async {
    final token = await TokenStore.readAccessToken();
    if (token == null) {
      throw Exception('No hay sesión activa. Iniciá sesión de nuevo.');
    }
    return {"Content-Type": "application/json", "Authorization": "Bearer $token"};
  }

  // ===== Auth (RF-AUTH-001..007) =====

  static Future<Map<String, dynamic>> registerClient({
    required String fullName,
    required String document,
    required String phone,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/auth/register/client");
    final response = await _client
        .post(
          url,
          headers: _jsonHeaders(),
          body: jsonEncode({
            "full_name": fullName,
            "document": document,
            "phone": phone,
            "password": password,
          }),
        )
        .timeout(_timeout);
    return _decodeOrThrow(response, "Error al registrar el cliente");
  }

  static Future<Map<String, dynamic>> registerTechnician({
    required String fullName,
    required String document,
    required String phone,
    required String password,
    required String specialty,
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse("$baseUrl/auth/register/technician");
    final response = await _client
        .post(
          url,
          headers: _jsonHeaders(),
          body: jsonEncode({
            "full_name": fullName,
            "document": document,
            "phone": phone,
            "password": password,
            "specialty": specialty,
            "latitude": latitude,
            "longitude": longitude,
          }),
        )
        .timeout(_timeout);
    return _decodeOrThrow(response, "Error al registrar el técnico");
  }

  static Future<Map<String, dynamic>> login({
    required String document,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/auth/login");
    final response = await _client
        .post(
          url,
          headers: _jsonHeaders(),
          body: jsonEncode({"document": document, "password": password}),
        )
        .timeout(_timeout);
    return _decodeOrThrow(response, "Credenciales inválidas");
  }

  static Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final url = Uri.parse("$baseUrl/auth/refresh");
    final response = await _client
        .post(
          url,
          headers: _jsonHeaders(),
          body: jsonEncode({"refresh_token": refreshToken}),
        )
        .timeout(_timeout);
    return _decodeOrThrow(response, "Error al renovar la sesión");
  }

  static Future<void> logout(String refreshToken) async {
    final url = Uri.parse("$baseUrl/auth/logout");
    final response = await _client
        .post(
          url,
          headers: _jsonHeaders(),
          body: jsonEncode({"refresh_token": refreshToken}),
        )
        .timeout(_timeout);
    await _decodeOrThrow(response, "Error al cerrar la sesión");
  }

  static Future<Map<String, dynamic>> me() async {
    final url = Uri.parse("$baseUrl/auth/me");
    final response = await _client
        .get(url, headers: await _authedHeaders())
        .timeout(_timeout);
    return _decodeOrThrow(response, "Error al cargar el perfil");
  }

  // ===== Solicitudes / bids =====

  static Future<Map<String, dynamic>> createServiceRequest({
    required int equipmentId,
    required String serviceType,
    required String description,
    required double latitude,
    required double longitude,
    double? budgetOffered,
  }) async {
    // RF-SR-001: el dueño sale del token autenticado; el payload NO lleva user_id.
    final url = Uri.parse("$baseUrl/services/");
    final response = await _client
        .post(
          url,
          headers: await _authedHeaders(),
          body: jsonEncode({
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
    required double priceOffered,
    required int estimatedTimeMinutes,
    required double transportCost,
    required double diagnosisCost,
  }) async {
    // RF-SR-002: el bid lleva los costos (>= 0, validado por backend) y el
    // técnico sale del token (no se envía technician_id).
    final url = Uri.parse("$baseUrl/services/bids/");
    final response = await _client
        .post(
          url,
          headers: await _authedHeaders(),
          body: jsonEncode({
            "service_request_id": serviceRequestId,
            "price_offered": priceOffered,
            "estimated_time_minutes": estimatedTimeMinutes,
            "transport_cost": transportCost,
            "diagnosis_cost": diagnosisCost,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al enviar la oferta: ${response.body}");
    }
  }

  // ===== S3 vertical del pacto — técnico (RF-SR-004/005/008, RF-MATCH-004) =====

  /// Radar del técnico: solicitudes cercanas `requested`/`bidding` desde el
  /// endpoint REAL `/api/technicians/requests/nearby/` (RF-MATCH-004). La
  /// ubicación sale del perfil del técnico en backend, no de params.
  static Future<List<Map<String, dynamic>>> fetchTechnicianRadar({
    double radiusKm = 10.0,
  }) async {
    final url = Uri.parse(
      "$baseUrl/technicians/requests/nearby/?radius_km=$radiusKm",
    );
    final response = await _client
        .get(url, headers: await _authedHeaders())
        .timeout(_timeout);
    final body = await _decodeOrThrow(response, "Error al cargar el radar");
    final requests = body['requests'] as List<dynamic>? ?? [];
    return requests.map((item) => item as Map<String, dynamic>).toList();
  }

  /// RF-SR-004: el técnico asignado registra las observaciones del diagnóstico.
  static Future<Map<String, dynamic>> registerDiagnosis({
    required int requestId,
    required String observations,
  }) async {
    final url = Uri.parse("$baseUrl/services/$requestId/diagnosis");
    return _postAuthed(url, {"observations": observations}, "registrar el diagnóstico");
  }

  /// RF-SR-005: el técnico asignado propone el pacto con desglose y observaciones.
  static Future<Map<String, dynamic>> proposeAgreement({
    required int requestId,
    required double laborCost,
    required double transportCost,
    required double diagnosisCost,
    String? observations,
  }) async {
    final url = Uri.parse("$baseUrl/services/$requestId/agreements/");
    return _postAuthed(
      url,
      {
        "labor_cost": laborCost,
        "transport_cost": transportCost,
        "diagnosis_cost": diagnosisCost,
        "observations": observations,
      },
      "proponer el pacto",
    );
  }

  /// RF-SR-008: el técnico asignado finaliza el servicio desde `in_progress`.
  static Future<Map<String, dynamic>> completeServiceRequest({
    required int requestId,
  }) async {
    final url = Uri.parse("$baseUrl/services/$requestId/complete");
    return _postAuthed(url, null, "finalizar el servicio");
  }

  /// POST autenticado genérico para el vertical del pacto (2xx -> JSON,
  /// cualquier otro -> Exception con status y detalle).
  static Future<Map<String, dynamic>> _postAuthed(
    Uri url,
    Map<String, dynamic>? body,
    String errorMessage,
  ) async {
    final response = await _client
        .post(
          url,
          headers: await _authedHeaders(),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decodeOrThrow(response, "Error al $errorMessage");
  }

  // ===== S3 vertical del pacto — cliente (RF-SR-003/006/007/009/010) =====

  /// Historial del cliente dueño (RF-SR-010): GET /api/services/my, fecha desc.
  static Future<List<Map<String, dynamic>>> fetchMyRequests() async {
    final url = Uri.parse("$baseUrl/services/my");
    final response = await _client
        .get(url, headers: await _authedHeaders())
        .timeout(_timeout);
    final body = await _decodeOrThrow(response, "Error al cargar el historial");
    final requests = body['requests'] as List<dynamic>? ?? [];
    return requests.map((item) => item as Map<String, dynamic>).toList();
  }

  /// Detalle con técnico y línea de tiempo (RF-SR-010): GET /api/services/{id}.
  static Future<Map<String, dynamic>> fetchServiceRequestDetail(
    int requestId,
  ) async {
    final url = Uri.parse("$baseUrl/services/$requestId");
    final response = await _client
        .get(url, headers: await _authedHeaders())
        .timeout(_timeout);
    return _decodeOrThrow(response, "Error al cargar el detalle");
  }

  /// RF-SR-003: el cliente dueño acepta un bid desde `bidding`.
  static Future<Map<String, dynamic>> acceptBid({
    required int requestId,
    required int bidId,
  }) async {
    final url = Uri.parse("$baseUrl/services/$requestId/bids/$bidId/accept");
    return _postAuthed(url, null, "aceptar la oferta");
  }

  /// RF-SR-006: el cliente dueño acepta el pacto -> in_progress.
  static Future<Map<String, dynamic>> acceptAgreement({
    required int requestId,
    required int agreementId,
  }) async {
    final url =
        Uri.parse("$baseUrl/services/$requestId/agreements/$agreementId/accept");
    return _postAuthed(url, null, "aceptar el pacto");
  }

  /// RF-SR-007: el cliente dueño rechaza el pacto -> mercado reabre.
  static Future<Map<String, dynamic>> rejectAgreement({
    required int requestId,
    required int agreementId,
  }) async {
    final url =
        Uri.parse("$baseUrl/services/$requestId/agreements/$agreementId/reject");
    return _postAuthed(url, null, "rechazar el pacto");
  }

  /// RF-SR-009: el cliente dueño cancela desde requested/bidding (atómico).
  static Future<Map<String, dynamic>> cancelServiceRequest({
    required int requestId,
  }) async {
    final url = Uri.parse("$baseUrl/services/$requestId/cancel");
    return _postAuthed(url, null, "cancelar la solicitud");
  }

  // ===== S4 ratings (RF-RAT-001..006) =====

  /// RF-RAT-001..003: el cliente dueño evalúa una solicitud COMPLETADA con 3
  /// sub-dimensiones 1-5 + comentario opcional <= 1000 (validado por backend,
  /// 422 si excede). Duplicado por solicitud -> 409 del servidor.
  static Future<Map<String, dynamic>> submitReview({
    required int requestId,
    required int punctuality,
    required int quality,
    required int professionalism,
    String? comment,
  }) async {
    final url = Uri.parse("$baseUrl/services/$requestId/review/");
    return _postAuthed(
      url,
      {
        "punctuality": punctuality,
        "quality": quality,
        "professionalism": professionalism,
        "comment": comment,
      },
      "enviar la calificación",
    );
  }

  static Future<List<Map<String, dynamic>>> fetchNearbyRequests({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    // RF-MATCH-006: endpoint REAL del radar del técnico
    // (/api/services/technicians-nearby/, no el /api/services/nearby inexistente).
    final url = Uri.parse(
      "$baseUrl/services/technicians-nearby/"
      "?latitude=$latitude&longitude=$longitude&radius_km=$radiusKm",
    );
    final response = await _client.get(url).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final technicians = body['technicians'] as List<dynamic>? ?? [];
      return technicians.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception("Error al buscar solicitudes: ${response.body}");
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
    final response = await _client.get(url).timeout(_timeout);

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
    final response = await _client.get(url).timeout(_timeout);

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