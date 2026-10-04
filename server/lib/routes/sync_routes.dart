import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth_middleware.dart';
import '../db/database.dart';
import '../util/json_response.dart';
import '../util/validation.dart';

/// `GET /v1/sync?since=<epochMs>` y `POST /v1/sync`: el teléfono es la única
/// fuente de verdad real de sus datos; este servidor sólo guarda un espejo.
/// Como hay un solo dispositivo por usuario, no hace falta resolver
/// conflictos entre clientes — basta con comparar `updatedAt` (ver
/// docs/API.md en la raíz del repo).
///
/// El formato de cada fila es el mismo `toJson()`/`fromJson()` que ya genera
/// drift en el teléfono (lib/data/database.g.dart), MENOS `userId`: aquí se
/// quita al responder y se añade (del token autenticado, nunca del cuerpo de
/// la petición) al guardar. Así ambos lados reusan su propio código generado
/// sin tener que traducir formatos a mano.
Router syncRoutes(ServerDatabase db) {
  final router = Router();

  router.get('/v1/sync', (Request request) async {
    final userId = userIdOf(request);
    final since = int.tryParse(request.url.queryParameters['since'] ?? '') ?? 0;
    final serverTimeMs = DateTime.now().millisecondsSinceEpoch;

    final accounts = await (db.select(db.accounts)..where((a) => a.userId.equals(userId) & a.updatedAt.isBiggerThanValue(since))).get();
    final categories = await (db.select(db.categories)..where((c) => c.userId.equals(userId) & c.updatedAt.isBiggerThanValue(since))).get();
    final transactions =
        await (db.select(db.transactions)..where((t) => t.userId.equals(userId) & t.updatedAt.isBiggerThanValue(since))).get();
    final budgets = await (db.select(db.budgets)..where((b) => b.userId.equals(userId) & b.updatedAt.isBiggerThanValue(since))).get();

    Map<String, dynamic> withoutUserId(Map<String, dynamic> json) => json..remove('userId');

    return jsonResponse(200, {
      'serverTimeMs': serverTimeMs,
      'epoch': await db.epoch(),
      'accounts': [for (final a in accounts) withoutUserId(a.toJson())],
      'categories': [for (final c in categories) withoutUserId(c.toJson())],
      'transactions': [for (final t in transactions) withoutUserId(t.toJson())],
      'budgets': [for (final b in budgets) withoutUserId(b.toJson())],
    });
  });

  router.post('/v1/sync', (Request request) async {
    final userId = userIdOf(request);
    final body = await readJsonBody(request);
    if (body == null) return errorResponse(400, 'Cuerpo JSON inválido.');

    List<Map<String, dynamic>> listOf(String key) {
      final value = body[key];
      if (value == null) return const [];
      if (value is! List) throw FormatException('"$key" debe ser una lista.');
      return value.cast<Map<String, dynamic>>();
    }

    try {
      final accountRows = listOf('accounts');
      final categoryRows = listOf('categories');
      final budgetRows = listOf('budgets');
      final transactionRows = listOf('transactions');

      for (final r in accountRows) {
        _requireString(r, 'id');
        if (!validAccountKinds.contains(r['kind'])) throw FormatException('accounts: kind inválido en ${r['id']}.');
      }
      for (final r in categoryRows) {
        _requireString(r, 'id');
        if (!validTxTypes.contains(r['type'])) throw FormatException('categories: type inválido en ${r['id']}.');
      }
      for (final r in budgetRows) {
        _requireString(r, 'id');
        if (!validBudgetKinds.contains(r['kind'])) throw FormatException('budgets: kind inválido en ${r['id']}.');
      }
      for (final r in transactionRows) {
        _requireString(r, 'id');
        if (!validTxTypes.contains(r['type'])) throw FormatException('transactions: type inválido en ${r['id']}.');
      }

      final serverTimeMs = DateTime.now().millisecondsSinceEpoch;
      await db.transaction(() async {
        await db.batch((b) {
          b.insertAll(
            db.accounts,
            [
              for (final r in accountRows)
                AccountsCompanion.insert(
                  id: r['id'] as String,
                  userId: userId,
                  name: r['name'] as String,
                  icon: r['icon'] as String,
                  kind: r['kind'] as String,
                  sortOrder: Value((r['sortOrder'] as num?)?.toInt() ?? 0),
                  createdAt: (r['createdAt'] as num).toInt(),
                  updatedAt: (r['updatedAt'] as num).toInt(),
                  deletedAt: Value((r['deletedAt'] as num?)?.toInt()),
                ),
            ],
            mode: InsertMode.insertOrReplace,
          );
          b.insertAll(
            db.categories,
            [
              for (final r in categoryRows)
                CategoriesCompanion.insert(
                  id: r['id'] as String,
                  userId: userId,
                  name: r['name'] as String,
                  icon: r['icon'] as String,
                  type: r['type'] as String,
                  sortOrder: Value((r['sortOrder'] as num?)?.toInt() ?? 0),
                  createdAt: (r['createdAt'] as num).toInt(),
                  updatedAt: (r['updatedAt'] as num).toInt(),
                  deletedAt: Value((r['deletedAt'] as num?)?.toInt()),
                ),
            ],
            mode: InsertMode.insertOrReplace,
          );
          b.insertAll(
            db.budgets,
            [
              for (final r in budgetRows)
                BudgetsCompanion.insert(
                  id: r['id'] as String,
                  userId: userId,
                  kind: r['kind'] as String,
                  amountMinor: (r['amountMinor'] as num).toInt(),
                  categoryId: Value(r['categoryId'] as String?),
                  createdAt: (r['createdAt'] as num).toInt(),
                  updatedAt: (r['updatedAt'] as num).toInt(),
                  deletedAt: Value((r['deletedAt'] as num?)?.toInt()),
                ),
            ],
            mode: InsertMode.insertOrReplace,
          );
          b.insertAll(
            db.transactions,
            [
              for (final r in transactionRows)
                TransactionsCompanion.insert(
                  id: r['id'] as String,
                  userId: userId,
                  type: r['type'] as String,
                  amountMinor: (r['amountMinor'] as num).toInt(),
                  categoryId: r['categoryId'] as String,
                  accountId: r['accountId'] as String,
                  note: Value(r['note'] as String?),
                  occurredAt: (r['occurredAt'] as num).toInt(),
                  createdAt: (r['createdAt'] as num).toInt(),
                  updatedAt: (r['updatedAt'] as num).toInt(),
                  deletedAt: Value((r['deletedAt'] as num?)?.toInt()),
                ),
            ],
            mode: InsertMode.insertOrReplace,
          );
        });
      });

      return jsonResponse(200, {'serverTimeMs': serverTimeMs});
    } on FormatException catch (e) {
      return errorResponse(400, e.message);
    } on TypeError {
      return errorResponse(400, 'Una o más filas tienen un campo con el tipo equivocado o faltante.');
    }
  });

  return router;
}

void _requireString(Map<String, dynamic> row, String key) {
  if (row[key] is! String || (row[key] as String).isEmpty) {
    throw FormatException('Falta o es inválido el campo "$key" en una fila.');
  }
}
