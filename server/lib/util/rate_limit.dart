import 'dart:convert';

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

String clientIp(Request request) {
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) return forwarded.split(',').first.trim();
  final connectionInfo = request.context['shelf.io.connection_info'];
  return connectionInfo?.toString() ?? 'unknown';
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
