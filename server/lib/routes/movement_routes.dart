import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../auth_middleware.dart';
import '../db/database.dart';
import '../util/category_matcher.dart';
import '../util/json_response.dart';
import '../util/period.dart';
import '../util/validation.dart';

/// `POST /v1/movements` (lo que usa el servicio externo para registrar un gasto/ingreso) y
/// `GET /v1/movements` (listar). La idea central: nunca adivinar una
/// categoría o cuenta ambigua — mejor devolver sugerencias y que quien llama
/// reintente, que crear datos en el lugar equivocado.
Router movementRoutes(ServerDatabase db) {
  final router = Router();
  const uuid = Uuid();

  router.post('/v1/movements', (Request request) async {
    final userId = userIdOf(request);
    final body = await readJsonBody(request);
    if (body == null) return errorResponse(400, 'Cuerpo JSON inválido.');

    final type = body['type'];
    if (type is! String || !validTxTypes.contains(type)) {
      return errorResponse(400, "type debe ser 'expense' o 'income'.");
    }

    int? amountMinor;
    if (body['amountMinor'] is num) {
      amountMinor = (body['amountMinor'] as num).round();
    } else if (body['amount'] is num) {
      amountMinor = ((body['amount'] as num) * 100).round();
    }
    if (amountMinor == null || amountMinor <= 0) {
      return errorResponse(400, 'Falta un monto válido: "amountMinor" (centavos) o "amount" (unidades, ej. 500.00).');
    }

    final categoryInput = body['category'];
    if (categoryInput is! String || categoryInput.trim().isEmpty) {
      return errorResponse(400, 'Falta "category" (nombre o id de una categoría existente).');
    }
    final categories =
        await (db.select(db.categories)..where((c) => c.userId.equals(userId) & c.deletedAt.isNull() & c.type.equals(type))).get();
    if (categories.isEmpty) {
      return errorResponse(
        409,
        'Todavía no hay categorías sincronizadas desde el teléfono. Abre la app con "Sincronizar con el servidor" activado al menos una vez.',
      );
    }
    final match = matchCategory(categoryInput, categories);
    if (!match.isFound) {
      return errorResponse(422, 'No reconozco la categoría "$categoryInput".', extra: {
        'suggestions': [for (final c in match.suggestions) c.name],
      });
    }

    final accounts = await (db.select(db.accounts)
          ..where((a) => a.userId.equals(userId) & a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
        .get();
    if (accounts.isEmpty) {
      return errorResponse(409, 'Todavía no hay cuentas sincronizadas desde el teléfono.');
    }
    final accountInput = body['account'];
    AccountRow account;
    if (accountInput is String && accountInput.trim().isNotEmpty) {
      final found = accounts.where((a) => a.id == accountInput || normalize(a.name) == normalize(accountInput)).toList();
      if (found.isEmpty) {
        return errorResponse(422, 'No reconozco la cuenta "$accountInput".', extra: {
          'suggestions': [for (final a in accounts) a.name],
        });
      }
      account = found.first;
    } else {
      account = accounts.first; // la primera por sortOrder, igual que "la predeterminada" en la app.
    }

    final noteInput = body['note'];
    final note = noteInput is String && noteInput.trim().isNotEmpty ? noteInput.trim() : null;
    final occurredAt = body['occurredAtMs'] is num ? (body['occurredAtMs'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = uuid.v4();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          userId: userId,
          type: type,
          amountMinor: amountMinor,
          categoryId: match.category!.id,
          accountId: account.id,
          note: Value(note),
          occurredAt: occurredAt,
          createdAt: now,
          updatedAt: now,
        ));

    return jsonResponse(201, {
      'id': id,
      'type': type,
      'amountMinor': amountMinor,
      'category': match.category!.name,
      'account': account.name,
      'note': note,
      'occurredAtMs': occurredAt,
    });
  });

  router.get('/v1/movements', (Request request) async {
    final userId = userIdOf(request);
    final params = request.url.queryParameters;
    final type = params['type'];
    if (type != null && !validTxTypes.contains(type)) {
      return errorResponse(400, "type debe ser 'expense' o 'income' si se indica.");
    }
    final Range? range;
    try {
      range = resolvePeriodRange(params['period'], DateTime.now());
    } on FormatException catch (e) {
      return errorResponse(400, e.message);
    }
    final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 100);

    final query = db.select(db.transactions).join([
      innerJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
      innerJoin(db.accounts, db.accounts.id.equalsExp(db.transactions.accountId)),
    ])
      ..where(db.transactions.userId.equals(userId) & db.transactions.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(db.transactions.occurredAt)])
      ..limit(limit);
    if (type != null) query.where(db.transactions.type.equals(type));
    if (range != null) {
      query.where(
        db.transactions.occurredAt.isBiggerOrEqualValue(range.start) & db.transactions.occurredAt.isSmallerThanValue(range.endExclusive),
      );
    }

    final rows = await query.get();
    return jsonResponse(200, [
      for (final r in rows)
        {
          'id': r.readTable(db.transactions).id,
          'type': r.readTable(db.transactions).type,
          'amountMinor': r.readTable(db.transactions).amountMinor,
          'category': r.readTable(db.categories).name,
          'account': r.readTable(db.accounts).name,
          'note': r.readTable(db.transactions).note,
          'occurredAtMs': r.readTable(db.transactions).occurredAt,
        },
    ]);
  });

  return router;
}
