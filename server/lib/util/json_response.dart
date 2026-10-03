import 'dart:convert';

import 'package:shelf/shelf.dart';

Response jsonResponse(int status, Object? data) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );

Response errorResponse(int status, String message, {Map<String, Object?>? extra}) =>
    jsonResponse(status, {'error': message, ...?extra});

/// Decodifica el cuerpo JSON de la petición; `null` (con un 400 ya resuelto en
/// [onInvalid]) si no es un JSON válido o no es un objeto.
Future<Map<String, dynamic>?> readJsonBody(Request request) async {
  try {
    final body = await request.readAsString();
    if (body.isEmpty) return {};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
