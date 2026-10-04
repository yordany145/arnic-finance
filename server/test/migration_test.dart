import 'dart:io';

import 'package:arnic_finance_server/db/database.dart';
import 'package:test/test.dart';

void main() {
  test('una base creada con el esquema v1 (sin user_configs) se actualiza sola a v2 y conserva sus datos', () async {
    final dir = Directory.systemTemp.createTempSync('arnic_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/server.db';

    // Simula una base de producción vieja: esquema completo, sin la tabla nueva y con user_version = 1.
    var db = ServerDatabase.file(path);
    await db.customStatement("INSERT INTO users (id, api_key_hash, created_at) VALUES ('u1', 'hash', 1)");
    await db.customStatement('DROP TABLE user_configs');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    db = ServerDatabase.file(path); // al abrir, drift ve user_version 1 < 2 y migra
    addTearDown(db.close);
    expect(await db.select(db.userConfigs).get(), isEmpty);
    expect((await db.select(db.users).get()).single.id, 'u1');
  });
}
