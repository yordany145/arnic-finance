import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../database.dart';
import '../mappers.dart';

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Stream<List<Category>> watch(TxType type) {
    final c = _db.categories;
    return (_db.select(c)
          ..where((r) => r.type.equalsValue(type) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.sortOrder), (r) => OrderingTerm.asc(r.name)]))
        .watch()
        .map((rows) => rows.map(categoryFromRow).toList());
  }

  @override
  Stream<List<Category>> watchByUsage(TxType type) {
    // Mismo criterio que usa el registro rápido nativo (QuickDb.kt).
    return _db
        .customSelect(
          'SELECT c.* FROM categories c '
          'LEFT JOIN transactions t ON t.category_id = c.id AND t.deleted_at IS NULL '
          'WHERE c.type = ? AND c.deleted_at IS NULL '
          'GROUP BY c.id ORDER BY COUNT(t.id) DESC, c.sort_order ASC, c.name ASC',
          variables: [Variable.withString(type.name)],
          readsFrom: {_db.categories, _db.transactions},
        )
        .watch()
        .map((rows) => rows.map((r) => categoryFromRow(_db.categories.map(r.data))).toList());
  }

  @override
  Future<Category?> getById(String id) async {
    final row = await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
    return row == null ? null : categoryFromRow(row);
  }

  @override
  Future<void> create({required String name, required String icon, required TxType type}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxOrder = _db.categories.sortOrder.max();
    final current = await (_db.selectOnly(_db.categories)
          ..addColumns([maxOrder])
          ..where(_db.categories.type.equalsValue(type)))
        .map((r) => r.read(maxOrder))
        .getSingle();
    await _db.into(_db.categories).insert(CategoriesCompanion.insert(
          id: _uuid.v4(),
          name: name.trim(),
          icon: icon,
          type: type,
          sortOrder: Value((current ?? -1) + 1),
          createdAt: now,
          updatedAt: now,
        ));
  }

  @override
  Future<void> update(String id, {required String name, required String icon}) async {
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
      name: Value(name.trim()),
      icon: Value(icon),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Borrado lógico: los movimientos antiguos conservan su categoría (y su
  /// nombre) en el historial. Siempre debe quedar al menos una por tipo.
  @override
  Future<void> delete(String id) async {
    final cat = await getById(id);
    if (cat == null) return;
    final remaining = await (_db.select(_db.categories)
          ..where((c) => c.type.equalsValue(cat.type) & c.deletedAt.isNull() & c.id.equals(id).not()))
        .get();
    if (remaining.isEmpty) {
      throw StateError('Debe existir al menos una categoría de ${cat.type.pluralLabel.toLowerCase()}.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}
