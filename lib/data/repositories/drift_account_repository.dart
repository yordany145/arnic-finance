import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../database.dart';
import '../mappers.dart';
import '../settings_keys.dart';

class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Stream<List<Account>> watch() {
    final a = _db.accounts;
    return (_db.select(a)
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.sortOrder), (r) => OrderingTerm.asc(r.createdAt)]))
        .watch()
        .map((rows) => rows.map(accountFromRow).toList());
  }

  @override
  Future<void> create({required String name, required String icon, required AccountKind kind}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxOrder = _db.accounts.sortOrder.max();
    final current = await (_db.selectOnly(_db.accounts)..addColumns([maxOrder])).map((r) => r.read(maxOrder)).getSingle();
    await _db.into(_db.accounts).insert(AccountsCompanion.insert(
          id: _uuid.v4(),
          name: name.trim(),
          icon: icon,
          kind: kind,
          sortOrder: Value((current ?? -1) + 1),
          createdAt: now,
          updatedAt: now,
        ));
  }

  @override
  Future<void> update(String id, {required String name, required String icon, required AccountKind kind}) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(AccountsCompanion(
      name: Value(name.trim()),
      icon: Value(icon),
      kind: Value(kind),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction(() async {
      final remaining = await (_db.select(_db.accounts)..where((a) => a.deletedAt.isNull() & a.id.equals(id).not())).get();
      if (remaining.isEmpty) throw StateError('Debe existir al menos una cuenta.');

      final now = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
          .write(AccountsCompanion(deletedAt: Value(now), updatedAt: Value(now)));

      // Si era la predeterminada, pasa a la primera que quede.
      final def = await (_db.select(_db.appSettings)..where((s) => s.key.equals(kSettingDefaultAccountId))).getSingleOrNull();
      if (def?.value == id) {
        remaining.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: kSettingDefaultAccountId, value: remaining.first.id));
      }
    });
  }
}
