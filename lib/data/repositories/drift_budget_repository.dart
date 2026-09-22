import 'dart:async';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:uuid/uuid.dart';

import '../../domain/budget.dart';
import '../../domain/enums.dart';
import '../../domain/repositories.dart';
import '../database.dart';

class DriftBudgetRepository implements BudgetRepository {
  DriftBudgetRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Budget _fromRows(BudgetRow b, CategoryRow? c) => Budget(
        id: b.id,
        kind: BudgetKind.values.byName(b.kind),
        amountMinor: b.amountMinor,
        categoryId: c?.id,
        categoryName: c?.name,
        categoryIcon: c?.icon,
      );

  @override
  Stream<List<Budget>> watch() {
    final b = _db.budgets;
    final c = _db.categories;
    return (_db.select(b)
              ..where((r) => r.deletedAt.isNull())
              ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .join([leftOuterJoin(c, c.id.equalsExp(b.categoryId))])
        .watch()
        .map((rows) => [for (final r in rows) _fromRows(r.readTable(b), r.readTableOrNull(c))]);
  }

  @override
  Stream<List<BudgetProgress>> watchProgress(DateTime now) {
    return watch().asyncExpand((budgetList) {
      if (budgetList.isEmpty) return Stream.value(const <BudgetProgress>[]);
      // Un stream por presupuesto (cada uno reacciona sólo a lo suyo) combinados en una lista.
      final streams = budgetList.map((budget) => _progressStream(budget, now));
      return _combineLatest(streams);
    });
  }

  Stream<BudgetProgress> _progressStream(Budget budget, DateTime now) {
    final t = _db.transactions;
    final start = DateTime(now.year, now.month).millisecondsSinceEpoch;
    final end = DateTime(now.year, now.month + 1).millisecondsSinceEpoch;
    final base = _db.selectOnly(t)
      ..where(t.deletedAt.isNull() & t.occurredAt.isBiggerOrEqualValue(start) & t.occurredAt.isSmallerThanValue(end));

    if (budget.kind == BudgetKind.savings) {
      // Neto = ingresos − gastos. `type` guarda 'income'/'expense': sumamos con signo vía CASE.
      final signedSum = CustomExpression<int>(
        "COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE -amount_minor END), 0)",
      );
      return (base..addColumns([signedSum])).map((r) => r.read(signedSum) ?? 0).watchSingle().map(
            (net) => BudgetProgress(budget: budget, currentMinor: net),
          );
    }

    final sum = t.amountMinor.sum();
    base.addColumns([sum]);
    base.where(t.type.equalsValue(TxType.expense));
    if (budget.kind == BudgetKind.category) base.where(t.categoryId.equals(budget.categoryId!));
    return base.map((r) => r.read(sum) ?? 0).watchSingle().map(
          (spent) => BudgetProgress(budget: budget, currentMinor: spent),
        );
  }

  /// Combina varios streams en un `List` que se re-emite cuando cualquiera cambia
  /// (equivalente mínimo a `Rx.combineLatestList`, sin añadir `rxdart` sólo para esto).
  Stream<List<T>> _combineLatest<T>(Iterable<Stream<T>> streams) {
    final list = streams.toList();
    late final List<T?> latest;
    late final StreamController<List<T>> controller;
    final subs = <StreamSubscription<T>>[];
    var pending = list.length;

    controller = StreamController<List<T>>.broadcast(
      onListen: () {
        latest = List<T?>.filled(list.length, null);
        pending = list.length;
        for (var i = 0; i < list.length; i++) {
          subs.add(list[i].listen((value) {
            if (latest[i] == null && pending > 0) pending--;
            latest[i] = value;
            if (pending == 0) controller.add(latest.cast<T>());
          }));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> createCategoryBudget({required String categoryId, required int amountMinor}) =>
      _create(BudgetKind.category, amountMinor, categoryId: categoryId);

  @override
  Future<void> createOverallExpenseBudget({required int amountMinor}) =>
      _create(BudgetKind.overallExpense, amountMinor);

  @override
  Future<void> createSavingsBudget({required int amountMinor}) => _create(BudgetKind.savings, amountMinor);

  Future<void> _create(BudgetKind kind, int amountMinor, {String? categoryId}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.budgets).insert(BudgetsCompanion.insert(
          id: _uuid.v4(),
          kind: kind.name,
          amountMinor: amountMinor,
          categoryId: Value(categoryId),
          createdAt: now,
          updatedAt: now,
        ));
  }

  @override
  Future<void> updateAmount(String id, int amountMinor) async {
    await (_db.update(_db.budgets)..where((b) => b.id.equals(id))).write(BudgetsCompanion(
      amountMinor: Value(amountMinor),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  @override
  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.budgets)..where((b) => b.id.equals(id)))
        .write(BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  @override
  Future<bool> markAlertIfNew(String budgetId, String periodKey, AlertLevel level) async {
    try {
      await _db.into(_db.budgetAlerts).insert(BudgetAlertsCompanion.insert(
            budgetId: budgetId,
            periodKey: periodKey,
            level: level.name,
            firedAt: DateTime.now().millisecondsSinceEpoch,
          ));
      return true; // se insertó: es la primera vez.
    } on SqliteException catch (e) {
      // SQLITE_CONSTRAINT (código primario 19): chocó con la clave primaria
      // budgetId+periodKey+level, o sea que ya se avisó. Cualquier otro error
      // (disco lleno, BD cerrada, etc.) se relanza: no debe confundirse con
      // "ya notificado" y quedar silenciado.
      if (e.resultCode == 19) return false;
      rethrow;
    }
  }
}
