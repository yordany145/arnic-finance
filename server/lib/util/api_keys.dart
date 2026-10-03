import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Genera una API key aleatoria de 256 bits, codificada en base64url sin
/// relleno (legible en una sola línea, sin caracteres que rompan URLs/headers).
String generateApiKey() {
  final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// La key en texto plano NUNCA se guarda (ver `Users.apiKeyHash` en tables.dart):
/// sólo este hash. Un SHA-256 simple es suficiente aquí porque la key ya tiene
/// 256 bits de entropía propia (no es una contraseña corta elegida por un
/// humano que necesite un KDF lento tipo bcrypt/argon2 contra fuerza bruta).
String hashApiKey(String apiKey) => sha256.convert(utf8.encode(apiKey)).toString();
