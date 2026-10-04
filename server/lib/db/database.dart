import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Users, Accounts, Categories, Transactions, Budgets, UserConfigs])
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
          // v2: configuración por usuario (tarjetas). Las bases creadas antes no la tienen.
          if (from < 2) await m.createTable(userConfigs);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
