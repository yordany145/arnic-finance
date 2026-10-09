import 'enums.dart';
import 'models.dart';

class BudgetSuggestion {
  const BudgetSuggestion({required this.category, required this.averageMinor, required this.suggestedMinor});

  final Category category;

  /// Gasto mensual promedio en esa categoría.
  final int averageMinor;

  /// Límite sugerido: el promedio redondeado hacia arriba a la centena de pesos.
  final int suggestedMinor;
}

/// Sugiere límites con base en el gasto de los meses ya cerrados (hasta 3). Sin ningún mes cerrado con
/// gastos no hay base honesta y devuelve vacío. [excludeCategoryIds]: categorías que ya tienen presupuesto.
List<BudgetSuggestion> suggestBudgets({
  required List<Movement> movements,
  required DateTime now,
  Set<String> excludeCategoryIds = const {},
  int maxItems = 4,
}) {
  final thisMonth = DateTime(now.year, now.month);
  final firstMonth = DateTime(now.year, now.month - 3);
  final totals = <String, int>{};
  final categories = <String, Category>{};
  final monthsWithData = <int>{};
  for (final m in movements) {
    if (m.type != TxType.expense) continue;
    final at = m.occurredAt;
    final month = DateTime(at.year, at.month);
    if (!month.isBefore(thisMonth) || month.isBefore(firstMonth)) continue;
    monthsWithData.add(month.year * 12 + month.month);
    totals[m.category.id] = (totals[m.category.id] ?? 0) + m.amountMinor;
    categories[m.category.id] = m.category;
  }
  if (monthsWithData.isEmpty) return const [];
  const hundredPesos = 10000;
  final result = <BudgetSuggestion>[];
  for (final entry in totals.entries) {
    if (excludeCategoryIds.contains(entry.key)) continue;
    final average = (entry.value / monthsWithData.length).round();
    if (average < hundredPesos) continue;
    result.add(BudgetSuggestion(
      category: categories[entry.key]!,
      averageMinor: average,
      suggestedMinor: ((average + hundredPesos - 1) ~/ hundredPesos) * hundredPesos,
    ));
  }
  result.sort((a, b) => b.averageMinor.compareTo(a.averageMinor));
  return result.take(maxItems).toList();
}
