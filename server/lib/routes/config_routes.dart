import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth_middleware.dart';
import '../db/database.dart';
import '../util/json_response.dart';
import '../util/validation.dart';

const _maxConfigBytes = 32 * 1024;

/// `GET /v1/config` y `PUT /v1/config`: configuración que la app edita (límites y días de
/// corte/pago de las tarjetas) y que el puente de correo lee para sus recordatorios y alertas.
///
/// Gana la edición más reciente: el cliente manda `updatedAt` (hora de su edición, en ms) y el
/// servidor rechaza con 409 una escritura que no sea más nueva que la guardada, para que un
/// teléfono con datos viejos no pise un cambio hecho desde otro lado.
Router configRoutes(ServerDatabase db) {
  final router = Router();

  router.get('/v1/config', (Request request) async {
    final userId = userIdOf(request);
    final row = await (db.select(db.userConfigs)..where((c) => c.userId.equals(userId))).getSingleOrNull();
    if (row == null) return jsonResponse(200, {'updatedAt': 0, 'config': <String, Object?>{}});
    return jsonResponse(200, {'updatedAt': row.updatedAt, 'config': jsonDecode(row.json)});
  });

  router.put('/v1/config', (Request request) async {
    final userId = userIdOf(request);
    final body = await readJsonBody(request);
    if (body == null) return errorResponse(400, 'Cuerpo JSON inválido.');
    final config = body['config'];
    final updatedAt = body['updatedAt'];
    if (config is! Map<String, dynamic>) return errorResponse(400, '"config" debe ser un objeto.');
    if (updatedAt is! int || updatedAt <= 0) return errorResponse(400, '"updatedAt" debe ser la hora de edición en milisegundos.');
    final problem = validateUserConfig(config);
    if (problem != null) return errorResponse(400, problem);
    final encoded = jsonEncode(config);
    if (utf8.encode(encoded).length > _maxConfigBytes) return errorResponse(413, 'La configuración es demasiado grande.');

    return db.transaction(() async {
      final current = await (db.select(db.userConfigs)..where((c) => c.userId.equals(userId))).getSingleOrNull();
      if (current != null && updatedAt <= current.updatedAt) {
        return errorResponse(409, 'Hay una configuración más reciente en el servidor.', extra: {'updatedAt': current.updatedAt});
      }
      await db.into(db.userConfigs).insertOnConflictUpdate(
            UserConfigsCompanion.insert(userId: userId, json: encoded, updatedAt: updatedAt),
          );
      return jsonResponse(200, {'updatedAt': updatedAt});
    });
  });

  return router;
}
