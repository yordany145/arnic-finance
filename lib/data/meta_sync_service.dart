import 'package:drift/drift.dart';

import 'database.dart';
import 'meta_sync_client.dart';
import 'meta_sync_prefs.dart';

/// Orquesta subir los cambios locales y bajar los del servidor. Como sólo hay
/// un teléfono por cuenta, no hace falta resolver conflictos entre
/// dispositivos: basta con comparar `updated_at` contra el último cursor
/// guardado (ver docs/API.md, sección "Protocolo de sincronización").
class MetaSyncService {
  MetaSyncService(this._db, this._client, this._prefs);

  final AppDatabase _db;
  final MetaSyncClient _client;
  final MetaSyncPrefs _prefs;

  Future<void> syncNow() async {
    if (!_prefs.isConfigured) throw MetaSyncException('No hay un servidor configurado todavía.');
    final serverUrl = _prefs.serverUrl!;
    final apiKey = _prefs.apiKey!;
    await _push(serverUrl, apiKey);
    await _pull(serverUrl, apiKey);
  }

  /// Reenvía y relee todo desde cero (p. ej. tras cambiar de servidor o si el
  /// espejo del servidor se perdió — ver la nota sobre almacenamiento efímero
  /// en docs/API.md).
  Future<void> fullResync() async {
    await _prefs.resetCursors();
    await syncNow();
  }

  Future<void> _push(String serverUrl, String apiKey) async {
    final since = _prefs.lastPushedAt;
    final accounts = await (_db.select(_db.accounts)..where((a) => a.updatedAt.isBiggerThanValue(since))).get();
    final categories = await (_db.select(_db.categories)..where((c) => c.updatedAt.isBiggerThanValue(since))).get();
    final budgets = await (_db.select(_db.budgets)..where((b) => b.updatedAt.isBiggerThanValue(since))).get();
    final transactions = await (_db.select(_db.transactions)..where((t) => t.updatedAt.isBiggerThanValue(since))).get();

    if (accounts.isEmpty && categories.isEmpty && budgets.isEmpty && transactions.isEmpty) return;

    final serverTimeMs = await _client.push(serverUrl: serverUrl, apiKey: apiKey, rows: {
      'accounts': [for (final a in accounts) a.toJson()],
      'categories': [for (final c in categories) c.toJson()],
      'budgets': [for (final b in budgets) b.toJson()],
      'transactions': [for (final t in transactions) t.toJson()],
    });
    await _prefs.setLastPushedAt(serverTimeMs);
  }

  Future<void> _pull(String serverUrl, String apiKey) async {
    final since = _prefs.lastPulledAt;
    final result = await _client.pull(serverUrl: serverUrl, apiKey: apiKey, since: since);
    final rows = result.rows;

    if (rows.values.every((list) => list.isEmpty)) {
      await _prefs.setLastPulledAt(result.serverTimeMs);
      return;
    }

    // Orden de claves foráneas: cuentas/categorías antes que presupuestos y
    // movimientos (igual que BackupService.restoreFromJson).
    await _db.transaction(() async {
      await _db.batch((b) {
        b.insertAll(_db.accounts, rows['accounts']!.map(AccountRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.categories, rows['categories']!.map(CategoryRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.budgets, rows['budgets']!.map(BudgetRow.fromJson), mode: InsertMode.insertOrReplace);
        b.insertAll(_db.transactions, rows['transactions']!.map(TxRow.fromJson), mode: InsertMode.insertOrReplace);
      });
    });
    await _prefs.setLastPulledAt(result.serverTimeMs);
  }
}
