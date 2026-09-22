import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../database.dart';
import '../mappers.dart';

class DriftMovementRepository implements MovementRepository {
  DriftMovementRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Expression<bool> _predicate(MovementFilter f, {required bool includeType}) {
    final t = _db.transactions;
    return Expression.and([
      t.deletedAt.isNull(),
      if (includeType && f.type != null) t.type.equalsValue(f.type!),
      if (f.categoryId != null) t.categoryId.equals(f.categoryId!),
      if (f.accountId != null) t.accountId.equals(f.accountId!),
      if (f.range != null) ...[
        t.occurredAt.isBiggerOrEqualValue(f.range!.start.millisecondsSinceEpoch),
        t.occurredAt.isSmallerThanValue(f.range!.endExclusive.millisecondsSinceEpoch),
      ],
      if (f.noteQuery != null && f.noteQuery!.isNotEmpty) t.note.like('%${f.noteQuery}%'),
    ]);
  }

  JoinedSelectStatement<HasResultSet, dynamic> _joined(MovementFilter f) {
    final t = _db.transactions;
    final c = _db.categories;
    final a = _db.accounts;
    final q = _db.select(t).join([
      innerJoin(c, c.id.equalsExp(t.categoryId)),
      innerJoin(a, a.id.equalsExp(t.accountId)),
    ])
      ..where(_predicate(f, includeType: true))
      ..orderBy([OrderingTerm.desc(t.occurredAt), OrderingTerm.desc(t.createdAt)]);
    if (f.limit != null) q.limit(f.limit!);
    return q;
  }

  @override
  Stream<List<Movement>> watch(MovementFilter filter) {
    return _joined(filter).watch().map((rows) => [
          for (final r in rows)
            movementFromRows(r.readTable(_db.transactions), r.readTable(_db.categories), r.readTable(_db.accounts)),
        ]);
  }

  @override
  Stream<PeriodSummary> watchSummary(MovementFilter filter) {
    final t = _db.transactions;
    final total = t.amountMinor.sum();
    final q = _db.selectOnly(t)
      ..addColumns([t.type, total])
      ..where(_predicate(filter, includeType: false))
      ..groupBy([t.type]);
    return q.watch().map((rows) {
      var income = 0, expense = 0;
      for (final r in rows) {
        final sum = r.read(total) ?? 0;
        if (r.readWithConverter(t.type) == TxType.income) {
          income = sum;
        } else {
          expense = sum;
        }
      }
      return PeriodSummary(incomeMinor: income, expenseMinor: expense);
    });
  }

  @override
  Future<Movement?> getById(String id) async {
    final t = _db.transactions;
    final c = _db.categories;
    final a = _db.accounts;
    final row = await (_db.select(t).join([
      innerJoin(c, c.id.equalsExp(t.categoryId)),
      innerJoin(a, a.id.equalsExp(t.accountId)),
    ])..where(t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return movementFromRows(row.readTable(t), row.readTable(c), row.readTable(a));
  }

  @override
  Future<String> add(MovementInput input) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await _db.into(_db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          type: input.type,
          amountMinor: input.amountMinor,
          categoryId: input.categoryId,
          accountId: input.accountId,
          note: Value(_cleanNote(input.note)),
          occurredAt: input.occurredAt.millisecondsSinceEpoch,
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  @override
  Future<void> update(String id, MovementInput input) async {
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(
      type: Value(input.type),
      amountMinor: Value(input.amountMinor),
      categoryId: Value(input.categoryId),
      accountId: Value(input.accountId),
      note: Value(_cleanNote(input.note)),
      occurredAt: Value(input.occurredAt.millisecondsSinceEpoch),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  @override
  Future<void> delete(String id) => _setDeleted(id, DateTime.now().millisecondsSinceEpoch);

  @override
  Future<void> restore(String id) => _setDeleted(id, null);

  Future<void> _setDeleted(String id, int? deletedAt) async {
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(
      deletedAt: Value(deletedAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  String? _cleanNote(String? note) {
    final n = note?.trim();
    return (n == null || n.isEmpty) ? null : n;
  }
}
