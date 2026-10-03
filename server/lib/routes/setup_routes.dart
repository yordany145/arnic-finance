import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../util/api_keys.dart';
import '../util/json_response.dart';
import '../util/rate_limit.dart';

/// Aprovisiona (o rota) la única API key de este servidor. Protegido por
/// `SETUP_TOKEN` (no por una API key, porque todavía no existe ninguna la
/// primera vez) para que no cualquiera en internet pueda crearse una cuenta
/// en tu servidor personal.
Router setupRoutes(ServerDatabase db, String setupToken, RateLimiter limiter) {
  final router = Router();
  const uuid = Uuid();

  router.post('/v1/setup', (Request request) async {
    if (!limiter.allow('setup:${clientIp(request)}')) {
      return errorResponse(429, 'Demasiados intentos. Espera un momento.');
    }
    if (request.headers['x-setup-token'] != setupToken) {
      return errorResponse(401, 'X-Setup-Token inválido o ausente.');
    }

    final body = await readJsonBody(request);
    if (body == null) return errorResponse(400, 'Cuerpo JSON inválido.');
    final rotate = body['rotate'] == true;

    final existing = await db.select(db.users).getSingleOrNull();
    final apiKey = generateApiKey();
    final hash = hashApiKey(apiKey);

    if (existing == null) {
      final id = uuid.v4();
      await db.into(db.users).insert(UsersCompanion.insert(id: id, apiKeyHash: hash, createdAt: DateTime.now().millisecondsSinceEpoch));
      return jsonResponse(201, {'userId': id, 'apiKey': apiKey});
    }

    if (!rotate) {
      return errorResponse(409, 'Ya hay una API key configurada. Envía {"rotate": true} para generar una nueva (invalida la anterior).');
    }
    await (db.update(db.users)..where((u) => u.id.equals(existing.id))).write(UsersCompanion(apiKeyHash: Value(hash)));
    return jsonResponse(200, {'userId': existing.id, 'apiKey': apiKey});
  });

  return router;
}
