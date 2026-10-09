import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_account_repository.dart';
import 'package:arnic_finance/data/repositories/drift_budget_repository.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/domain/assistant/assistant_engine.dart';
import 'package:arnic_finance/domain/assistant/assistant_intent.dart';
import 'package:arnic_finance/domain/assistant/period_parser.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_DO'));

  late AppDatabase db;
  late DriftMovementRepository movements;
  late DriftAccountRepository accounts;
  late DriftBudgetRepository budgets;
  late AssistantEngine engine;

  final now = DateTime(2026, 9, 15);

  setUp(() {
    db = AppDatabase.inMemory();
    movements = DriftMovementRepository(db);
    accounts = DriftAccountRepository(db);
    budgets = DriftBudgetRepository(db);
    engine = AssistantEngine(movements, accounts, budgets, 'RD\$', now);
  });
  tearDown(() => db.close());

  Future<void> addExpense(int minor, String cat, DateTime at, {String? note, String account = kDefaultAccountId}) => movements.add(
        MovementInput(type: TxType.expense, amountMinor: minor, categoryId: cat, accountId: account, occurredAt: at, note: note),
      );
  Future<void> addIncome(int minor, DateTime at, {String account = kDefaultAccountId}) => movements.add(
        MovementInput(type: TxType.income, amountMinor: minor, categoryId: 'inc_salary', accountId: account, occurredAt: at),
      );

  test('balance = ingresos - gastos, sin importar el período', () async {
    await addIncome(500000, now);
    await addExpense(150000, 'exp_food', DateTime(2026, 1, 1)); // fuera del mes: igual cuenta
    final answer = await engine.answer(const BalanceIntent());
    expect(answer.text, contains('RD\$3,500'));
  });

  test('totales por categoría y período', () async {
    await addExpense(100000, 'exp_food', now);
    await addExpense(50000, 'exp_food', DateTime(2026, 8, 1)); // mes pasado: no cuenta
    await addExpense(999900, 'exp_fuel', now); // otra categoría: no cuenta
    final period = extractPeriod('este mes', now);
    final answer = await engine.answer(TotalsIntent(type: TxType.expense, period: period, categoryId: 'exp_food', categoryName: 'Comida'));
    expect(answer.text, contains('RD\$1,000'));
    expect(answer.text, contains('Comida'));
  });

  test('totales sin movimientos: lo dice claramente, no "RD\$0"', () async {
    final period = extractPeriod('este mes', now);
    final answer = await engine.answer(TotalsIntent(type: TxType.expense, period: period, categoryId: 'exp_food', categoryName: 'Comida'));
    expect(answer.text, contains('No registraste'));
  });

  test('comparar períodos: detecta que gastó más', () async {
    await addExpense(200000, 'exp_food', now); // este mes
    await addExpense(100000, 'exp_food', DateTime(2026, 8, 20)); // mes pasado
    final current = extractPeriod('este mes', now)!;
    final previous = extractPeriod('mes pasado', now)!;
    final answer = await engine.answer(
      CompareIntent(type: TxType.expense, currentLabel: 'este mes', current: current, previous: previous),
    );
    expect(answer.text, contains('más'));
    expect(answer.text, contains('100%')); // el doble
  });

  test('top categorías ordena de mayor a menor', () async {
    await addExpense(300000, 'exp_food', now);
    await addExpense(100000, 'exp_fuel', now);
    await addExpense(500000, 'exp_transport', now);
    final answer = await engine.answer(TopCategoriesIntent(type: TxType.expense, period: extractPeriod('este mes', now)));
    final food = answer.text.indexOf('Comida');
    final transport = answer.text.indexOf('Transporte');
    final fuel = answer.text.indexOf('Combustible');
    expect(transport, lessThan(food)); // 5000 > 3000
    expect(food, lessThan(fuel)); // 3000 > 1000
  });

  test('estado de presupuestos incluye el porcentaje', () async {
    await budgets.createCategoryBudget(categoryId: 'exp_food', amountMinor: 100000);
    await addExpense(90000, 'exp_food', now);
    final answer = await engine.answer(const BudgetsStatusIntent());
    expect(answer.text, contains('90%'));
    expect(answer.text, contains('cerca del límite'));
  });

  test('saldo por cuenta: cada cuenta ve sólo sus movimientos', () async {
    await accounts.create(name: 'Banco', icon: '🏦', kind: AccountKind.bank);
    final bank = (await accounts.watch().first).last;
    await addExpense(50000, 'exp_food', now); // Efectivo
    await addIncome(1000000, now, account: bank.id); // Banco
    final answer = await engine.answer(const AccountsStatusIntent());
    expect(answer.text, contains('Efectivo: -RD\$500'));
    expect(answer.text, contains('Banco: RD\$10,000'));
  });

  test('buscar por nota encuentra y suma los resultados', () async {
    await addExpense(50000, 'exp_subscriptions', now, note: 'Netflix mensual');
    await addExpense(30000, 'exp_food', now, note: 'Netflix y comida'); // coincide igual
    await addExpense(20000, 'exp_food', now, note: 'otra cosa');
    final answer = await engine.answer(const SearchMovementsIntent(query: 'netflix'));
    expect(answer.text, contains('Encontré 2'));
    expect(answer.text, contains('RD\$800')); // 500 + 300 con signo, en total negativo mostrado con guion
  });

  test('crear alerta de categoría: la crea como presupuesto real', () async {
    final answer = await engine.answer(
      const CreateAlertIntent(goal: AlertGoal.categoryLimit, amountMinor: 500000, categoryId: 'exp_food', categoryName: 'Comida'),
    );
    expect(answer.text, contains('Comida'));
    expect(answer.pending, isNull);
    final list = await budgets.watch().first;
    expect(list.single.categoryId, 'exp_food');
    expect(list.single.amountMinor, 500000);
  });

  test('crear alerta de categoría que ya existe: actualiza en vez de duplicar', () async {
    await budgets.createCategoryBudget(categoryId: 'exp_food', amountMinor: 300000);
    final answer = await engine.answer(
      const CreateAlertIntent(goal: AlertGoal.categoryLimit, amountMinor: 500000, categoryId: 'exp_food', categoryName: 'Comida'),
    );
    expect(answer.text, contains('actualicé'));
    final list = await budgets.watch().first;
    expect(list, hasLength(1)); // no se duplicó
    expect(list.single.amountMinor, 500000);
  });

  test('crear alerta sin monto: pide el dato y recuerda la plantilla', () async {
    final answer = await engine.answer(
      const CreateAlertIntent(goal: AlertGoal.categoryLimit, categoryId: 'exp_food', categoryName: 'Comida'),
    );
    expect(answer.pending, isNotNull);
    expect(answer.pending!.missing, 'amount');
    expect(await budgets.watch().first, isEmpty); // no crea nada a medias
  });

  test('meta de ahorro nueva', () async {
    final answer = await engine.answer(const CreateAlertIntent(goal: AlertGoal.savingsGoal, amountMinor: 1000000));
    expect(answer.text, contains('ahorres'));
    final list = await budgets.watch().first;
    expect(list.single.kind.name, 'savings');
  });

  group('registrar movimientos', () {
    test('crea el movimiento en la cuenta predeterminada y confirma', () async {
      final answer = await engine.answer(const RegisterMovementIntent(
        type: TxType.expense,
        amountMinor: 50000,
        categoryId: 'exp_food',
        categoryName: 'Comida',
        note: 'almuerzo',
      ));
      expect(answer.text, contains('RD\$500'));
      expect(answer.text, contains('deshacer'));
      expect(answer.registeredId, isNotNull);
      final saved = await movements.getById(answer.registeredId!);
      expect((saved!.amountMinor, saved.category.id, saved.account.id, saved.note), (50000, 'exp_food', kDefaultAccountId, 'almuerzo'));
    });

    test('"de ayer" usa la fecha de ayer', () async {
      final answer = await engine.answer(const RegisterMovementIntent(
        type: TxType.expense,
        amountMinor: 10000,
        categoryId: 'exp_food',
        categoryName: 'Comida',
        yesterday: true,
      ));
      final saved = await movements.getById(answer.registeredId!);
      expect(saved!.occurredAt, DateTime(2026, 9, 14));
      expect(answer.text, contains('de ayer'));
    });

    test('respeta la cuenta nombrada', () async {
      await accounts.create(name: 'Banco', icon: '🏦', kind: AccountKind.bank);
      final bank = (await accounts.watch().first).firstWhere((a) => a.name == 'Banco');
      final answer = await engine.answer(RegisterMovementIntent(
        type: TxType.income,
        amountMinor: 100000,
        categoryId: 'inc_salary',
        categoryName: 'Salario',
        accountId: bank.id,
      ));
      expect((await movements.getById(answer.registeredId!))!.account.id, bank.id);
    });
  });
}
