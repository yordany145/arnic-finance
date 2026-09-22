import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_budget_repository.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/domain/budget.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftBudgetRepository budgets;
  late DriftMovementRepository movements;

  setUp(() {
    db = AppDatabase.inMemory();
    budgets = DriftBudgetRepository(db);
    movements = DriftMovementRepository(db);
  });
  tearDown(() => db.close());

  final now = DateTime(2026, 9, 15);

  Future<void> addExpense(int minor, String cat, DateTime at) => movements.add(
        MovementInput(type: TxType.expense, amountMinor: minor, categoryId: cat, accountId: kDefaultAccountId, occurredAt: at),
      );
  Future<void> addIncome(int minor, DateTime at) => movements.add(
        MovementInput(type: TxType.income, amountMinor: minor, categoryId: 'inc_salary', accountId: kDefaultAccountId, occurredAt: at),
      );

  test('presupuesto de categoría: sólo cuenta esa categoría y este mes', () async {
    await budgets.createCategoryBudget(categoryId: 'exp_food', amountMinor: 100000);
    await addExpense(40000, 'exp_food', now);
    await addExpense(50000, 'exp_food', now);
    await addExpense(999900, 'exp_fuel', now); // otra categoría: no cuenta
    await addExpense(500000, 'exp_food', DateTime(2026, 8, 20)); // mes pasado: no cuenta

    final progress = await budgets.watchProgress(now).first;
    expect(progress.single.currentMinor, 90000);
    expect(progress.single.ratio, closeTo(0.9, 0.0001));
    expect(progress.single.level, AlertLevel.approaching);
  });

  test('límite general: suma todos los gastos del mes, no los ingresos', () async {
    await budgets.createOverallExpenseBudget(amountMinor: 100000);
    await addExpense(60000, 'exp_food', now);
    await addExpense(60000, 'exp_fuel', now);
    await addIncome(999999, now);

    final p = (await budgets.watchProgress(now).first).single;
    expect(p.currentMinor, 120000);
    expect(p.isOver, isTrue);
  });

  test('meta de ahorro: ingresos menos gastos del mes', () async {
    await budgets.createSavingsBudget(amountMinor: 100000);
    await addIncome(300000, now);
    await addExpense(250000, 'exp_food', now);

    final p = (await budgets.watchProgress(now).first).single;
    expect(p.currentMinor, 50000);
    expect(p.level, isNull); // 50% de la meta
  });

  test('el progreso reacciona a nuevos movimientos (stream)', () async {
    await budgets.createOverallExpenseBudget(amountMinor: 100000);
    final values = <int>[];
    final sub = budgets.watchProgress(now).listen((list) => values.add(list.single.currentMinor));
    await pumpEventQueue();
    await addExpense(30000, 'exp_food', now);
    await pumpEventQueue();
    await addExpense(90000, 'exp_food', now);
    await pumpEventQueue();
    await sub.cancel();
    expect(values, [0, 30000, 120000]);
  });

  test('markAlertIfNew: true sólo la primera vez por presupuesto+período+nivel', () async {
    await budgets.createOverallExpenseBudget(amountMinor: 100000);
    final id = (await budgets.watch().first).single.id;

    expect(await budgets.markAlertIfNew(id, '2026-09', AlertLevel.approaching), isTrue);
    expect(await budgets.markAlertIfNew(id, '2026-09', AlertLevel.approaching), isFalse); // repetido
    expect(await budgets.markAlertIfNew(id, '2026-09', AlertLevel.reached), isTrue); // otro nivel: sí
    expect(await budgets.markAlertIfNew(id, '2026-10', AlertLevel.approaching), isTrue); // otro mes: sí
  });

  test('eliminar y editar un presupuesto', () async {
    await budgets.createCategoryBudget(categoryId: 'exp_food', amountMinor: 50000);
    final b = (await budgets.watch().first).single;
    await budgets.updateAmount(b.id, 70000);
    expect((await budgets.watch().first).single.amountMinor, 70000);
    await budgets.delete(b.id);
    expect(await budgets.watch().first, isEmpty);
  });
}
