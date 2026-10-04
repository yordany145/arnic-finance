import 'models.dart';

class MonthTotals {
  const MonthTotals({required this.month, required this.expenseMinor, required this.incomeMinor});

  /// Primer día del mes, en hora local.
  final DateTime month;
  final int expenseMinor;
  final int incomeMinor;
  int get netMinor => incomeMinor - expenseMinor;
}

class CategoryTotal {
  const CategoryTotal({required this.category, required this.minor});

  final Category category;
  final int minor;
}

DateTime monthOf(DateTime t) => DateTime(t.year, t.month);

/// Los últimos [months] meses terminando en el de [now], del más viejo al más nuevo (incluye los meses sin movimientos).
List<MonthTotals> monthlyTotals(List<Movement> movements, DateTime now, {int months = 6}) {
  final first = DateTime(now.year, now.month - (months - 1));
  final expense = <DateTime, int>{};
  final income = <DateTime, int>{};
  for (final m in movements) {
    final key = monthOf(m.occurredAt);
    final bucket = m.type.isExpense ? expense : income;
    bucket[key] = (bucket[key] ?? 0) + m.amountMinor;
  }
  return [
    for (var i = 0; i < months; i++)
      () {
        final month = DateTime(first.year, first.month + i);
        return MonthTotals(month: month, expenseMinor: expense[month] ?? 0, incomeMinor: income[month] ?? 0);
      }(),
  ];
}

/// Gasto del mes de [month] agrupado por categoría, de mayor a menor.
List<CategoryTotal> expenseByCategory(List<Movement> movements, DateTime month) {
  final key = monthOf(month);
  final totals = <String, int>{};
  final categories = <String, Category>{};
  for (final m in movements) {
    if (!m.type.isExpense || monthOf(m.occurredAt) != key) continue;
    totals[m.category.id] = (totals[m.category.id] ?? 0) + m.amountMinor;
    categories[m.category.id] = m.category;
  }
  return [for (final e in totals.entries) CategoryTotal(category: categories[e.key]!, minor: e.value)]..sort((a, b) => b.minor.compareTo(a.minor));
}
