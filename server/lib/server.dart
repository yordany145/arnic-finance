import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'db/database.dart';
import 'routes/movement_routes.dart';
import 'routes/reference_routes.dart';
import 'routes/setup_routes.dart';
import 'routes/summary_routes.dart';
import 'routes/sync_routes.dart';
import 'util/json_response.dart';
import 'util/rate_limit.dart';

/// Arma el handler HTTP completo. `/v1/setup` y `/health` son públicos (el
/// primero se protege a sí mismo con `X-Setup-Token`); todo lo demás bajo
/// `/v1/` exige `Authorization: Bearer <api_key>`.
///
/// Los routers por defecto (`Router()`, sin `notFoundHandler` propio) hacen
/// que un `mount` que no encontró ruta deje seguir probando el siguiente
/// `mount` del router que lo contiene (devuelven `Router.routeNotFound`, no
/// un 404 real) — por eso el orden de los `mount` de abajo no importa para la
/// autenticación: cada grupo sólo responde a sus propias rutas.
Handler buildHandler(ServerDatabase db, {required String setupToken}) {
  final setupLimiter = RateLimiter(maxRequests: 5, window: const Duration(minutes: 1));
  final apiLimiter = RateLimiter(maxRequests: 120, window: const Duration(minutes: 1));

  final publicRoutes = Router()
    ..mount('/', setupRoutes(db, setupToken, setupLimiter).call)
    ..get('/health', (Request _) => jsonResponse(200, {'ok': true}));

  final protectedRoutes = Router()
    ..mount('/', movementRoutes(db).call)
    ..mount('/', referenceRoutes(db).call)
    ..mount('/', summaryRoutes(db).call)
    ..mount('/', syncRoutes(db).call);

  final protectedHandler = const Pipeline()
      .addMiddleware(rateLimitMiddleware(apiLimiter, keyOf: (r) => 'api:${clientIp(r)}'))
      .addMiddleware(requireApiKey(db))
      .addHandler(protectedRoutes.call);

  final root = Router()
    ..mount('/', publicRoutes.call)
    ..mount('/', protectedHandler);

  return const Pipeline().addMiddleware(logRequests()).addHandler(root.call);
}
