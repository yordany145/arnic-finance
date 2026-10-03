import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth_middleware.dart';
import '../db/database.dart';
import '../util/json_response.dart';

/// `GET /v1/categories` y `GET /v1/accounts`: para que quien integra la API
/// (p. ej. la lógica detrás de un servicio externo) sepa qué nombres
/// existen de verdad antes de intentar registrar un movimiento.
Router referenceRoutes(ServerDatabase db) {
  final router = Router();

  router.get('/v1/categories', (Request request) async {
    final userId = userIdOf(request);
    final type = request.url.queryParameters['type'];
    if (type != null && type != 'expense' && type != 'income') {
      return errorResponse(400, "type debe ser 'expense' o 'income' si se indica.");
    }
    final query = db.select(db.categories)..where((c) => c.userId.equals(userId) & c.deletedAt.isNull());
    if (type != null) query.where((c) => c.type.equals(type));
    final rows = await query.get();
    return jsonResponse(200, [
      for (final c in rows) {'id': c.id, 'name': c.name, 'icon': c.icon, 'type': c.type},
    ]);
  });

  router.get('/v1/accounts', (Request request) async {
    final userId = userIdOf(request);
    final rows = await (db.select(db.accounts)..where((a) => a.userId.equals(userId) & a.deletedAt.isNull())).get();
    return jsonResponse(200, [
      for (final a in rows) {'id': a.id, 'name': a.name, 'icon': a.icon, 'kind': a.kind},
    ]);
  });

  return router;
}
