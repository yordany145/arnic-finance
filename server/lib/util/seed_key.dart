import 'package:uuid/uuid.dart';

import '../db/database.dart';

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// Si la base no tiene ningún usuario y [hash] es un SHA-256 en hexadecimal (la variable de entorno `API_KEY_HASH`),
/// crea el usuario con esa clave. Así la API key sobrevive a que la base se recree (Render gratis es efímero):
/// el teléfono, que es la fuente de verdad, vuelve a subir los datos, y nadie tiene que generar ni copiar otra clave.
///
/// Solo se guarda el hash, igual que con una clave generada; no es reversible (la clave tiene 256 bits).
/// Nunca pisa un usuario existente. Devuelve `true` si lo creó.
Future<bool> seedApiKeyHash(ServerDatabase db, String? hash) async {
  final value = hash?.trim().toLowerCase();
  if (value == null || value.isEmpty) return false;
  if (!_sha256Hex.hasMatch(value)) throw FormatException('API_KEY_HASH debe ser un SHA-256 en hexadecimal (64 caracteres).');
  if (await db.select(db.users).getSingleOrNull() != null) return false;
  await db.into(db.users).insert(UsersCompanion.insert(id: const Uuid().v4(), apiKeyHash: value, createdAt: DateTime.now().millisecondsSinceEpoch));
  return true;
}
