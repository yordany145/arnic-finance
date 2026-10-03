import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth_middleware.dart';
import '../db/database.dart';
import '../util/json_response.dart';
import '../util/period.dart';

/// `GET /v1/summary?period=today|yesterday|week|month|all` — mismo cálculo
/// que `DriftMovementRepository.watchSummary` del lado Flutter, en una sola
/// consulta (aquí no hace falta que sea un stream).
Router summaryRoutes(ServerDatabase db) {
  final router = Router();

  router.get('/v1/summary', (Request request) async {
    final userId = userIdOf(request);
    final periodParam = request.url.queryParameters['period'];
    final Range? range;
    try {
      range = resolvePeriodRange(periodParam, DateTime.now());
    } on FormatException catch (e) {
      return errorResponse(400, e.message);
    }

    final total = db.transactions.amountMinor.sum();
    final query = db.selectOnly(db.transactions)
      ..addColumns([db.transactions.type, total])
      ..where(db.transactions.userId.equals(userId) & db.transactions.deletedAt.isNull())
      ..groupBy([db.transactions.type]);
    if (range != null) {
      query.where(
        db.transactions.occurredAt.isBiggerOrEqualValue(range.start) & db.transactions.occurredAt.isSmallerThanValue(range.endExclusive),
      );
    }

    final rows = await query.get();
    var income = 0, expense = 0;
    for (final r in rows) {
      final sum = r.read(total) ?? 0;
      if (r.read(db.transactions.type) == 'income') {
        income = sum;
      } else {
        expense = sum;
      }
    }
    return jsonResponse(200, {
      'period': periodParam ?? 'all',
      'incomeMinor': income,
      'expenseMinor': expense,
      'balanceMinor': income - expense,
    });
  });

  return router;
}
