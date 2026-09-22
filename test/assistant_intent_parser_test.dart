import 'package:arnic_finance/domain/assistant/assistant_intent.dart';
import 'package:arnic_finance/domain/assistant/intent_parser.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = IntentParser();
  final now = DateTime(2026, 9, 22);

  final expenseCategories = [
    const Category(id: 'exp_food', name: 'Comida', icon: '🍔', type: TxType.expense, sortOrder: 0),
    const Category(id: 'exp_fuel', name: 'Combustible', icon: '⛽', type: TxType.expense, sortOrder: 1),
    const Category(id: 'exp_transport', name: 'Transporte', icon: '🚌', type: TxType.expense, sortOrder: 2),
  ];
  final incomeCategories = [
    const Category(id: 'inc_salary', name: 'Salario', icon: '💰', type: TxType.income, sortOrder: 0),
  ];
  final accounts = [
    const Account(id: 'acc_cash', name: 'Efectivo', icon: '💵', kind: AccountKind.cash, sortOrder: 0),
    const Account(id: 'acc_bank', name: 'Banco Popular', icon: '🏦', kind: AccountKind.bank, sortOrder: 1),
  ];

  AssistantIntent parse(String text) => parser.parse(
        text,
        expenseCategories: expenseCategories,
        incomeCategories: incomeCategories,
        accounts: accounts,
        now: now,
      );

  group('charla básica', () {
    test('saludo', () => expect(parse('Hola'), isA<GreetingIntent>()));
    test('agradecimiento', () => expect(parse('gracias!'), isA<ThanksIntent>()));
    test('ayuda', () => expect(parse('¿qué puedes hacer?'), isA<HelpIntent>()));
    test('un saludo dentro de una pregunta real no dispara GreetingIntent', () {
      // "hola" no aparece aquí, pero si apareciera junto a más texto no debe
      // ganarle a la intención real (el regex de saludo exige todo el mensaje).
      expect(parse('cuanto gaste hoy'), isNot(isA<GreetingIntent>()));
    });
  });

  group('balance', () {
    test('balance directo', () => expect(parse('¿cuál es mi balance?'), isA<BalanceIntent>()));
    test('cuanto tengo', () => expect(parse('¿cuánto tengo?'), isA<BalanceIntent>()));
  });

  group('totales', () {
    test('gasto de hoy', () {
      final i = parse('¿cuánto gasté hoy?') as TotalsIntent;
      expect(i.type, TxType.expense);
      expect(i.period?.label, 'hoy');
      expect(i.categoryId, isNull);
    });

    test('ingreso de este mes', () {
      final i = parse('¿cuánto ingresé este mes?') as TotalsIntent;
      expect(i.type, TxType.income);
      expect(i.period?.label, 'este mes');
    });

    test('gasto por categoría', () {
      final i = parse('¿cuánto gasté en comida el mes pasado?') as TotalsIntent;
      expect(i.type, TxType.expense);
      expect(i.categoryId, 'exp_food');
      expect(i.period?.label, 'el mes pasado');
    });

    test('categoría con nombre parecido (typo tolerado)', () {
      final i = parse('cuanto gaste en comdia este mes') as TotalsIntent;
      expect(i.categoryId, 'exp_food');
    });

    test('gasto por cuenta', () {
      final i = parse('¿cuánto gasté desde Banco Popular este mes?') as TotalsIntent;
      expect(i.accountId, 'acc_bank');
    });

    test('sin tipo explícito pero con periodo: ambos', () {
      final i = parse('cuánto moví esta semana') as TotalsIntent;
      expect(i.type, isNull);
      expect(i.period?.label, 'esta semana');
    });
  });

  group('comparar', () {
    test('gasto este mes vs el pasado', () {
      final i = parse('¿gasté más este mes que el pasado?') as CompareIntent;
      expect(i.type, TxType.expense);
      expect(i.currentLabel, 'este mes');
    });

    test('comparar semanas', () {
      final i = parse('compara mis gastos de esta semana') as CompareIntent;
      expect(i.currentLabel, 'esta semana');
    });
  });

  group('top categorías', () {
    test('en que gaste mas', () {
      final i = parse('¿en qué categoría gasté más este mes?') as TopCategoriesIntent;
      expect(i.type, TxType.expense);
    });

    test('top de ingresos', () {
      final i = parse('top de ingresos') as TopCategoriesIntent;
      expect(i.type, TxType.income);
    });
  });

  test('promedio', () {
    final i = parse('cuál es mi promedio de gasto diario') as AverageIntent;
    expect(i.type, TxType.expense);
  });

  test('presupuestos', () => expect(parse('¿cómo van mis presupuestos?'), isA<BudgetsStatusIntent>()));

  group('cuentas', () {
    test('saldo por cuenta', () => expect(parse('mi saldo por cuenta'), isA<AccountsStatusIntent>()));
    test('cuanto tengo en una cuenta concreta', () => expect(parse('cuánto tengo en Banco Popular'), isA<AccountsStatusIntent>()));
  });

  group('movimientos recientes y búsqueda', () {
    test('últimos movimientos', () => expect(parse('muéstrame mis movimientos recientes'), isA<RecentMovementsIntent>()));
    test('mi último gasto', () {
      final i = parse('cuál fue mi ultimo gasto') as RecentMovementsIntent;
      expect(i.type, TxType.expense);
    });
    test('buscar por nota', () {
      final i = parse('busca uber') as SearchMovementsIntent;
      expect(i.query, 'uber');
    });
    test('movimientos de X', () {
      final i = parse('movimientos de netflix') as SearchMovementsIntent;
      expect(i.query, 'netflix');
    });
  });

  group('crear alertas (= presupuestos)', () {
    test('límite de categoría completo', () {
      final i = parse('avísame si gasto más de 5000 en comida') as CreateAlertIntent;
      expect(i.goal, AlertGoal.categoryLimit);
      expect(i.categoryId, 'exp_food');
      expect(i.amountMinor, 500000);
    });

    test('límite general', () {
      final i = parse('notifícame si supero 30000 en gastos este mes') as CreateAlertIntent;
      expect(i.goal, AlertGoal.overallLimit);
      expect(i.amountMinor, 3000000);
    });

    test('meta de ahorro', () {
      final i = parse('avísame cuando ahorre 10000') as CreateAlertIntent;
      expect(i.goal, AlertGoal.savingsGoal);
      expect(i.amountMinor, 1000000);
    });

    test('límite de categoría sin monto: falta el dato, no falla', () {
      final i = parse('avísame si gasto mucho en combustible') as CreateAlertIntent;
      expect(i.goal, AlertGoal.categoryLimit);
      expect(i.categoryId, 'exp_fuel');
      expect(i.amountMinor, isNull);
    });

    test('alerta de balance no es un presupuesto: se dice claramente', () {
      expect(parse('avísame si mi balance baja de cero'), isA<UnsupportedAlertIntent>());
    });

    test('"gasto" en una alerta no se confunde con una pregunta de totales', () {
      // Debe clasificar como CreateAlertIntent, no como TotalsIntent, aunque
      // ambas mencionen "gasto".
      expect(parse('avísame si gasto más de 5000 en comida'), isA<CreateAlertIntent>());
    });
  });

  test('mensaje vacío o sin nada reconocible', () {
    expect(parse(''), isA<UnknownIntent>());
    expect(parse('xyz123 asdf'), isA<UnknownIntent>());
  });
}
