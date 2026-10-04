import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Users, Accounts, Categories, Transactions, Budgets, UserConfigs, ServerMeta])
class ServerDatabase extends _$ServerDatabase {
  ServerDatabase(super.executor);

  factory ServerDatabase.file(String path) => ServerDatabase(
        NativeDatabase.createInBackground(
          File(path),
          setup: (raw) {
            raw.execute('PRAGMA journal_mode = WAL;');
            raw.execute('PRAGMA busy_timeout = 5000;');
          },
        ),
      );

  factory ServerDatabase.inMemory() => ServerDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2: configuración por usuario (tarjetas) y datos del servidor (epoch). Las bases creadas antes no las tienen.
          if (from < 2) {
            await m.createTable(userConfigs);
            await m.createTable(serverMeta);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Identificador de ESTA base de datos (ver [ServerMeta]); se crea la primera vez que se pide.
  Future<String> epoch() => transaction(() async {
        final row = await (select(serverMeta)..where((m) => m.key.equals('epoch'))).getSingleOrNull();
        if (row != null) return row.value;
        final id = const Uuid().v4();
        await into(serverMeta).insert(ServerMetaCompanion.insert(key: 'epoch', value: id));
        return id;
      });
}
