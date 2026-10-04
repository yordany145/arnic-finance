import 'package:drift/drift.dart';

import '../domain/card_config.dart';
import 'card_settings_store.dart';
import 'database.dart';
import 'server_sync_client.dart';
import 'server_sync_prefs.dart';

/// Orquesta subir los cambios locales y bajar los del servidor. Como sólo hay
/// un teléfono por cuenta, no hace falta resolver conflictos entre
/// dispositivos: basta con comparar `updated_at` contra el último cursor
/// guardado (ver docs/API.md, sección "Protocolo de sincronización").
class ServerSyncService {
  ServerSyncService(this._db, this._client, this._prefs, {this.cardStore, this.onConfigChanged});

  final AppDatabase _db;
  final ServerSyncClient _client;
  final ServerSyncPrefs _prefs;
  final CardSettingsStore? cardStore;
  final void Function()? onConfigChanged;

  Future<void> syncNow() async {
    if (!_prefs.isConfigured) throw ServerSyncException('No hay un servidor configurado todavía.');
    final serverUrl = _prefs.serverUrl!;
    final apiKey = _prefs.apiKey!;
    await _syncData(serverUrl, apiKey, mayRetry: true);
    await _syncCardSettings(serverUrl, apiKey);
  }

  /// Sube lo nuevo y baja lo del servidor. Si el servidor perdió su base y la recreó (cambió su `epoch`), lo que ya
  /// enviamos ya no está allí aunque nuestros cursores digan que sí: se reinician y se vuelve a subir todo, una sola vez.
  Future<void> _syncData(String serverUrl, String apiKey, {required bool mayRetry}) async {
    final hadSyncedBefore = _prefs.lastPushedAt > 0 || _prefs.lastPulledAt > 0; // antes de subir: la subida mueve los cursores
    await _push(serverUrl, apiKey);
    final serverWasReset = await _pull(serverUrl, apiKey, hadSyncedBefore: hadSyncedBefore);
    if (serverWasReset && mayRetry) {
      await _prefs.resetCursors();
      await _syncData(serverUrl, apiKey, mayRetry: false);
    }
  }

  /// Gana la edición más reciente. Un fallo aquí no debe hacer fallar la sincronización de movimientos
  /// (que ya terminó bien): la configuración se reintenta en la próxima.
  Future<void> _syncCardSettings(String serverUrl, String apiKey) async {
    final store = cardStore;
    if (store == null) return;
    try {
      final remote = await _client.getConfig(serverUrl: serverUrl, apiKey: apiKey);
      if (remote == null) return;
      final local = store.read();
      if (remote.updatedAt > local.updatedAt) {
        await store.write(CardSettings.fromServerConfig(remote.config, remote.updatedAt));
        onConfigChanged?.call();
      } else if (local.updatedAt > remote.updatedAt) {
        await _client.putConfig(serverUrl: serverUrl, apiKey: apiKey, config: local.toServerConfig(), updatedAt: local.updatedAt);
      }
    } on ServerSyncException {
      // ver comentario de arriba
    }
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

  /// Devuelve `true` si el servidor cambió de `epoch` desde la última vez (es decir, perdió su base).
  Future<bool> _pull(String serverUrl, String apiKey, {required bool hadSyncedBefore}) async {
    final since = _prefs.lastPulledAt;
    final result = await _client.pull(serverUrl: serverUrl, apiKey: apiKey, since: since);
    final rows = result.rows;

    final previousEpoch = _prefs.serverEpoch;
    // Un servidor con epoch que no es el que conocíamos = base nueva. Si nunca habíamos visto un epoch pero ya habíamos
    // subido datos, es el primer despliegue con esta función (el contenedor nuevo parte vacío): también hay que volver a subir.
    final serverWasReset = result.epoch != null && result.epoch != previousEpoch && (previousEpoch != null || hadSyncedBefore);
    if (result.epoch != null) await _prefs.setServerEpoch(result.epoch!);

    if (rows.values.every((list) => list.isEmpty)) {
      await _prefs.setLastPulledAt(result.serverTimeMs);
      return serverWasReset;
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
    return serverWasReset;
  }
}
