import 'package:arnic_finance/domain/budget.dart';
import 'package:flutter_test/flutter_test.dart';

Budget _cat(String id, int amount) =>
    Budget(id: id, kind: BudgetKind.category, amountMinor: amount, categoryId: 'exp_food', categoryName: 'Comida', categoryIcon: '🍔');

Budget _overall(int amount) => Budget(id: 'ov', kind: BudgetKind.overallExpense, amountMinor: amount);

Budget _savings(int amount) => Budget(id: 'sav', kind: BudgetKind.savings, amountMinor: amount);

void main() {
  test('monthPeriodKey con ceros a la izquierda', () {
    expect(monthPeriodKey(DateTime(2026, 9, 15)), '2026-09');
    expect(monthPeriodKey(DateTime(2026, 12, 1)), '2026-12');
  });

  group('BudgetProgress: gasto (categoría o general)', () {
    test('tranquilo por debajo de 80%', () {
      final p = BudgetProgress(budget: _cat('a', 100000), currentMinor: 50000);
      expect(p.ratio, 0.5);
      expect(p.level, isNull);
      expect(p.isOver, isFalse);
    });

    test('acercándose exactamente en 80%', () {
      final p = BudgetProgress(budget: _overall(100000), currentMinor: 80000);
      expect(p.level, AlertLevel.approaching);
      expect(p.isOver, isFalse);
    });

    test('llega exactamente al límite', () {
      final p = BudgetProgress(budget: _overall(100000), currentMinor: 100000);
      expect(p.level, AlertLevel.reached);
      expect(p.isOver, isTrue);
    });

    test('se pasa del límite', () {
      final p = BudgetProgress(budget: _cat('a', 100000), currentMinor: 150000);
      expect(p.ratio, 1.5);
      expect(p.level, AlertLevel.reached);
      expect(p.isOver, isTrue);
    });
  });

  group('BudgetProgress: meta de ahorro', () {
    test('mes en rojo: no hay aviso (no es "acercarse")', () {
      final p = BudgetProgress(budget: _savings(50000), currentMinor: -10000);
      expect(p.level, isNull);
      expect(p.isOver, isFalse); // el "over" de gasto no aplica al ahorro
    });

    test('casi llega a la meta', () {
      final p = BudgetProgress(budget: _savings(50000), currentMinor: 42000);
      expect(p.level, AlertLevel.approaching);
    });

    test('meta cumplida (o superada)', () {
      expect(BudgetProgress(budget: _savings(50000), currentMinor: 50000).level, AlertLevel.reached);
      expect(BudgetProgress(budget: _savings(50000), currentMinor: 90000).level, AlertLevel.reached);
    });
  });

  test('título e icono por tipo', () {
    expect(_cat('a', 1).title, 'Comida');
    expect(_overall(1).title, 'Límite general de gastos');
    expect(_savings(1).title, 'Meta de ahorro');
    expect(_cat('a', 1).icon, '🍔');
    expect(_overall(1).icon, '🚦');
    expect(_savings(1).icon, '🐷');
  });
}
