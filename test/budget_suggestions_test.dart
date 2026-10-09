import 'package:arnic_finance/domain/budget_suggestions.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const food = Category(id: 'exp_food', name: 'Comida', icon: '🍔', type: TxType.expense, sortOrder: 0);
  const fuel = Category(id: 'exp_fuel', name: 'Combustible', icon: '⛽', type: TxType.expense, sortOrder: 1);
  const tiny = Category(id: 'exp_tiny', name: 'Chiquito', icon: '🔹', type: TxType.expense, sortOrder: 2);
  const acc = Account(id: 'a', name: 'Efectivo', icon: '💵', kind: AccountKind.cash, sortOrder: 0);
  final now = DateTime(2026, 10, 9);

  Movement mov(Category c, int pesos, DateTime at, {TxType type = TxType.expense}) =>
      Movement(id: '${c.id}$at$pesos', type: type, amountMinor: pesos * 100, category: c, account: acc, occurredAt: at);

  test('sin meses cerrados no hay base y no sugiere nada', () {
    expect(suggestBudgets(movements: [mov(food, 4000, DateTime(2026, 10, 2))], now: now), isEmpty);
  });

  test('promedia los meses cerrados con datos y redondea hacia arriba a la centena', () {
    final list = suggestBudgets(
      movements: [
        mov(food, 3000, DateTime(2026, 9, 5)),
        mov(food, 1050, DateTime(2026, 8, 20)),
        mov(fuel, 5000, DateTime(2026, 9, 10)),
        mov(food, 9999, DateTime(2026, 10, 2)), // mes en curso: no cuenta
      ],
      now: now,
    );
    expect(list.map((s) => s.category.id), ['exp_fuel', 'exp_food']); // por promedio descendente
    final foodSuggestion = list.last;
    expect(foodSuggestion.averageMinor, 202500); // (3000 + 1050) / 2 meses
    expect(foodSuggestion.suggestedMinor, 210000);
    expect(list.first.suggestedMinor, 250000); // 5000 / 2 meses con datos
  });

  test('ignora ingresos, categorías con presupuesto y montos insignificantes', () {
    final list = suggestBudgets(
      movements: [
        mov(food, 4000, DateTime(2026, 9, 5)),
        mov(food, 8000, DateTime(2026, 9, 6), type: TxType.income),
        mov(fuel, 2000, DateTime(2026, 9, 7)),
        mov(tiny, 50, DateTime(2026, 9, 8)),
      ],
      now: now,
      excludeCategoryIds: {'exp_fuel'},
    );
    expect(list.map((s) => s.category.id), ['exp_food']);
    expect(list.single.suggestedMinor, 400000);
  });

  test('respeta el máximo y no mira más de 3 meses atrás', () {
    final list = suggestBudgets(
      movements: [mov(food, 9000, DateTime(2026, 5, 5)), mov(fuel, 3000, DateTime(2026, 9, 5))],
      now: now,
    );
    expect(list.map((s) => s.category.id), ['exp_fuel']);
    expect(suggestBudgets(movements: [mov(food, 100, DateTime(2026, 9, 1)), mov(fuel, 100, DateTime(2026, 9, 1))], now: now, maxItems: 1), hasLength(1));
  });
}
