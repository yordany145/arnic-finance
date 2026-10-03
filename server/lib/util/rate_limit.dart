import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Ventana deslizante en memoria, por IP. Basta para un servidor de una sola
/// instancia como este (no hay varias réplicas detrás de un balanceador que
/// necesiten compartir el contador).
class RateLimiter {
  RateLimiter({required this.maxRequests, required this.window});

  final int maxRequests;
  final Duration window;
  final Map<String, List<DateTime>> _hits = {};

  bool allow(String key) {
    final now = DateTime.now();
    final hits = _hits.putIfAbsent(key, () => []);
    hits.removeWhere((t) => now.difference(t) > window);
    if (hits.length >= maxRequests) return false;
    hits.add(now);
    return true;
  }
}

/// IP del cliente para el limitador. Detrás de un proxy (Render) el proxy AÑADE
/// la IP real al FINAL de `X-Forwarded-For`; las entradas anteriores las puede
/// escribir cualquiera, así que usar la primera permitiría saltarse el límite
/// cambiando el encabezado en cada petición. Por eso se toma la última.
String clientIp(Request request) {
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.trim().isNotEmpty) return forwarded.split(',').last.trim();
  final connectionInfo = request.context['shelf.io.connection_info'];
  if (connectionInfo is HttpConnectionInfo) return connectionInfo.remoteAddress.address;
  return 'unknown';
}

/// Comparación en tiempo constante (no revela cuántos caracteres acertó un intento).
bool constantTimeEquals(String? a, String b) {
  if (a == null) return false;
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < y.length; i++) {
    diff |= (i < x.length ? x[i] : 0) ^ y[i];
  }
  return diff == 0;
}

Middleware rateLimitMiddleware(RateLimiter limiter, {required String Function(Request) keyOf}) {
  return (Handler inner) {
    return (Request request) async {
      if (!limiter.allow(keyOf(request))) {
        return Response(
          429,
          body: jsonEncode({'error': 'Demasiadas solicitudes. Intenta de nuevo en un momento.'}),
          headers: {'content-type': 'application/json'},
        );
      }
      return inner(request);
    };
  };
}
