import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_account_repository.dart';
import 'package:arnic_finance/data/repositories/drift_category_repository.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/repositories/drift_settings_repository.dart';
import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/domain/date_range.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:arnic_finance/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftMovementRepository movements;
  late DriftCategoryRepository categories;
  late DriftAccountRepository accounts;
  late DriftSettingsRepository settings;

  setUp(() {
    db = AppDatabase.inMemory();
    movements = DriftMovementRepository(db);
    categories = DriftCategoryRepository(db);
    accounts = DriftAccountRepository(db);
    settings = DriftSettingsRepository(db);
  });
  tearDown(() => db.close());

  MovementInput input(TxType type, int minor, String cat, DateTime at, {String? note}) => MovementInput(
        type: type,
        amountMinor: minor,
        categoryId: cat,
        accountId: kDefaultAccountId,
        occurredAt: at,
        note: note,
      );

  test('la base se siembra con las categorías, cuenta y ajustes iniciales', () async {
    final exp = await categories.watch(TxType.expense).first;
    expect(exp.map((c) => c.name), [
      'Comida', 'Transporte', 'Combustible', 'Compras', 'Entretenimiento', 'Salud',
      'Hogar', 'Servicios', 'Educación', 'Suscripciones', 'Otros',
    ]);
    final inc = await categories.watch(TxType.income).first;
    expect(inc.map((c) => c.name), ['Salario', 'Negocio', 'Transferencia', 'Regalo', 'Otros']);
    expect((await accounts.watch().first).single.name, 'Efectivo');
    expect(await settings.watchCurrencySymbol().first, 'RD\$');
    expect(await settings.watchDefaultAccountId().first, kDefaultAccountId);
  });

  test('agregar, listar, resumir y filtrar por tipo/categoría/fecha', () async {
    await movements.add(input(TxType.expense, 35000, 'exp_food', DateTime(2025, 9, 20, 13), note: '  almuerzo '));
    await movements.add(input(TxType.expense, 150000, 'exp_fuel', DateTime(2025, 10, 14, 23, 59)));
    await movements.add(input(TxType.income, 2500000, 'inc_salary', DateTime(2025, 10, 1)));
    await movements.add(input(TxType.expense, 99900, 'exp_food', DateTime(2025, 9, 14, 23, 59))); // fuera del rango
    await movements.add(input(TxType.expense, 10000, 'exp_food', DateTime(2025, 10, 15))); // fuera del rango

    final range = DateRange.days(DateTime(2025, 9, 15), DateTime(2025, 10, 14));
    final all = await movements.watch(MovementFilter(range: range)).first;
    expect(all, hasLength(3));
    expect(all.first.occurredAt, DateTime(2025, 10, 14, 23, 59)); // más reciente primero
    expect(all.last.note, 'almuerzo'); // se recorta el espacio

    final s = await movements.watchSummary(MovementFilter(range: range)).first;
    expect(s.incomeMinor, 2500000);
    expect(s.expenseMinor, 185000);
    expect(s.balanceMinor, 2315000);

    expect(await movements.watch(MovementFilter(range: range, type: TxType.income)).first, hasLength(1));
    expect(await movements.watch(MovementFilter(range: range, categoryId: 'exp_food')).first, hasLength(1));
    expect(await movements.watch(const MovementFilter(limit: 2)).first, hasLength(2));

    final total = await movements.watchSummary(const MovementFilter()).first;
    expect(total.expenseMinor, 35000 + 150000 + 99900 + 10000);
  });

  test('editar, borrar (lógico) y restaurar', () async {
    final id = await movements.add(input(TxType.expense, 1000, 'exp_food', DateTime(2025, 9, 1)));
    await movements.update(id, input(TxType.income, 2000, 'inc_gift', DateTime(2025, 9, 2), note: 'x'));
    final m = (await movements.getById(id))!;
    expect((m.type, m.amountMinor, m.category.id, m.note), (TxType.income, 2000, 'inc_gift', 'x'));

    await movements.delete(id);
    expect(await movements.watch(const MovementFilter()).first, isEmpty);
    expect((await movements.watchSummary(const MovementFilter()).first).incomeMinor, 0);
    await movements.restore(id);
    expect(await movements.watch(const MovementFilter()).first, hasLength(1));
  });

  test('los montos deben ser positivos', () async {
    expect(() => movements.add(input(TxType.expense, 0, 'exp_food', DateTime.now())), throwsA(anything));
  });

  test('categorías: crear, editar, borrar; un movimiento conserva la categoría borrada', () async {
    await categories.create(name: 'Mascotas', icon: '🐶', type: TxType.expense);
    var list = await categories.watch(TxType.expense).first;
    expect(list.last.name, 'Mascotas');
    expect(list.last.sortOrder, 11);

    await categories.update(list.last.id, name: 'Perro', icon: '🐕');
    final id = await movements.add(input(TxType.expense, 500, list.last.id, DateTime.now()));
    await categories.delete(list.last.id);

    list = await categories.watch(TxType.expense).first;
    expect(list.any((c) => c.name == 'Perro'), isFalse);
    final m = (await movements.getById(id))!;
    expect(m.category.name, 'Perro');
    expect(m.category.isDeleted, isTrue);
  });

  test('no se puede borrar la última categoría de un tipo', () async {
    final inc = await categories.watch(TxType.income).first;
    for (final c in inc.skip(1)) {
      await categories.delete(c.id);
    }
    expect(() => categories.delete(inc.first.id), throwsStateError);
  });

  test('categorías por uso: la más usada primero', () async {
    for (var i = 0; i < 3; i++) {
      await movements.add(input(TxType.expense, 100, 'exp_fuel', DateTime.now()));
    }
    await movements.add(input(TxType.expense, 100, 'exp_health', DateTime.now()));
    final byUse = await categories.watchByUsage(TxType.expense).first;
    expect(byUse.take(2).map((c) => c.id), ['exp_fuel', 'exp_health']);
    expect(byUse[2].id, 'exp_food'); // empate en 0 usos → orden original
    expect(byUse, hasLength(11));
  });

  test('cuentas: varias, y al borrar la predeterminada se reasigna', () async {
    await accounts.create(name: 'Banco Popular', icon: '🏦', kind: AccountKind.bank);
    final list = await accounts.watch().first;
    expect(list.map((a) => a.name), ['Efectivo', 'Banco Popular']);

    await accounts.delete(kDefaultAccountId);
    expect((await accounts.watch().first).single.name, 'Banco Popular');
    expect(await settings.watchDefaultAccountId().first, list.last.id);
    expect(() => accounts.delete(list.last.id), throwsStateError);
  });

  test('moneda configurable', () async {
    await settings.setCurrencySymbol(' US\$ ');
    expect(await settings.watchCurrencySymbol().first, 'US\$');
  });
}
