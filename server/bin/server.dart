import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:arnic_finance_server/db/database.dart';
import 'package:arnic_finance_server/server.dart';
import 'package:arnic_finance_server/util/seed_key.dart';

/// Variables de entorno:
///   SETUP_TOKEN (obligatoria) — secreto para aprovisionar la única API key
///     (ver docs/API.md en la raíz del repo, sección "Primer arranque").
///   PORT (opcional, por defecto 8080) — Render/Cloud Run la fijan solos.
///   API_KEY_HASH (opcional) — SHA-256 de la API key; si la base está vacía se crea el usuario con esa clave, así sobrevive a
///     que Render recree el contenedor. Si regeneras la key, actualiza esta variable.
///   DB_PATH (opcional, por defecto ./arnic_server.db) — en Render, apunta a
///     un volumen persistente o los datos se pierden en cada despliegue.
Future<void> main() async {
  final setupToken = Platform.environment['SETUP_TOKEN'];
  if (setupToken == null || setupToken.isEmpty) {
    stderr.writeln('Falta la variable de entorno SETUP_TOKEN. Define un secreto largo antes de arrancar el servidor.');
    exit(1);
  }

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final dbPath = Platform.environment['DB_PATH'] ?? 'arnic_server.db';

  final db = ServerDatabase.file(dbPath);
  try {
    if (await seedApiKeyHash(db, Platform.environment['API_KEY_HASH'])) {
      // ignore: avoid_print
      print('Base nueva: usuario creado con la clave de API_KEY_HASH (los datos los repone el teléfono al sincronizar).');
    }
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
  final handler = buildHandler(db, setupToken: setupToken);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print (es el log de arranque del proceso, no de una petición)
  print('Arnic Finance API escuchando en el puerto ${server.port} (base de datos: $dbPath)');
}
