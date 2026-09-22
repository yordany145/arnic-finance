import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// Copia de seguridad completa en un único JSON: exportar/restaurar sin
/// depender de ningún servidor (coherente con que la app es 100% local).
///
/// No incluye `budget_alerts` (sólo son marcas de qué avisos ya se enviaron,
/// no datos del usuario): tras restaurar, un presupuesto que ya había cruzado
/// un umbral puede volver a avisar una vez, lo cual es aceptable.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const _formatVersion = 1;

  Future<String> exportJson() async {
    final map = {
      'format': _formatVersion,
      'schemaVersion': AppDatabase.kSchemaVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'accounts': (await _db.select(_db.accounts).get()).map((r) => r.toJson()).toList(),
      'categories': (await _db.select(_db.categories).get()).map((r) => r.toJson()).toList(),
      'transactions': (await _db.select(_db.transactions).get()).map((r) => r.toJson()).toList(),
      'budgets': (await _db.select(_db.budgets).get()).map((r) => r.toJson()).toList(),
      'appSettings': (await _db.select(_db.appSettings).get()).map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Reemplaza TODOS los datos actuales por los del archivo. Es destructivo a
  /// propósito (restaurar una copia = volver a ese estado exacto): la
  /// pantalla que llama a esto debe confirmar con el usuario antes de invocarlo.
  Future<void> restoreFromJson(String jsonStr) async {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonStr) as Map<String, dynamic>;
    } on FormatException {
      throw const FormatException('El archivo no es una copia de seguridad válida (JSON inválido).');
    }
    if (map['format'] != _formatVersion) {
      throw const FormatException('Este archivo no es una copia de seguridad de Arnic Finance, o es de un formato futuro.');
    }

    List<Map<String, dynamic>> rows(String key) => (map[key] as List? ?? []).cast<Map<String, dynamic>>();

    await _db.transaction(() async {
      // Primero se borra en orden inverso a las claves foráneas (lo que
      // referencia antes que lo referenciado), luego se reinserta al revés
      // (lo referenciado antes que lo que lo referencia).
      await _db.delete(_db.budgetAlerts).go();
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.appSettings).go();

      await _db.batch((b) {
        b.insertAll(_db.accounts, rows('accounts').map(AccountRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.categories, rows('categories').map(CategoryRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.budgets, rows('budgets').map(BudgetRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.transactions, rows('transactions').map(TxRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.appSettings, rows('appSettings').map(SettingRow.fromJson), mode: InsertMode.insertOrReplace);
      });
    });
  }
}
