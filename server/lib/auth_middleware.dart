import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'db/database.dart';
import 'util/api_keys.dart';

/// Clave usada en `request.context` para pasar el `userId` ya autenticado a
/// los handlers de ruta.
const kUserIdContextKey = 'userId';

Response _unauthorized(String message) => Response(
      401,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );

/// Exige `Authorization: Bearer <apiKey>` y resuelve el `userId` dueño de esa
/// key. No distingue "key inválida" de "key no existe" en el mensaje (evita
/// dar pistas), y nunca compara la key contra la base en texto plano: sólo
/// compara hashes.
Middleware requireApiKey(ServerDatabase db) {
  return (Handler inner) {
    return (Request request) async {
      final header = request.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) {
        return _unauthorized('Falta el encabezado Authorization: Bearer <api_key>.');
      }
      final apiKey = header.substring('Bearer '.length).trim();
      if (apiKey.isEmpty) return _unauthorized('API key vacía.');

      final hash = hashApiKey(apiKey);
      final user = await (db.select(db.users)..where((u) => u.apiKeyHash.equals(hash))).getSingleOrNull();
      if (user == null) return _unauthorized('API key inválida.');

      return inner(request.change(context: {kUserIdContextKey: user.id}));
    };
  };
}

String userIdOf(Request request) => request.context[kUserIdContextKey]! as String;
