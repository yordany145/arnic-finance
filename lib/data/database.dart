import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../domain/enums.dart';
import 'seed.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Accounts, Categories, Transactions, AppSettings, Budgets, BudgetAlerts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Base local en [path]. WAL + `busy_timeout` permiten que el registro rápido
  /// nativo escriba en el mismo archivo mientras la app está abierta.
  factory AppDatabase.file(String path) => AppDatabase(
        NativeDatabase.createInBackground(
          File(path),
          setup: (raw) {
            raw.execute('PRAGMA journal_mode = WAL;');
            raw.execute('PRAGMA busy_timeout = 5000;');
          },
        ),
      );

  /// Sólo para pruebas.
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  /// Versión del esquema. También es `PRAGMA user_version`, que el código nativo
  /// comprueba antes de escribir. Al subirla, actualiza también
  /// `QuickDb.SUPPORTED_SCHEMA` (Kotlin) y `QuickDb.supportedSchema` (Swift).
  static const int kSchemaVersion = 2;

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedDefaults(this);
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2: presupuestos mensuales y el registro de avisos ya enviados.
          if (from < 2) {
            await m.createTable(budgets);
            await m.createTable(budgetAlerts);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
