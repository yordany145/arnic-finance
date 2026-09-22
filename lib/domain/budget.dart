import 'enums.dart';

/// Presupuesto mensual (se reinicia cada mes calendario, igual que "Este mes"
/// del historial). Tres formas de usarlo:
///  • [category]: límite de gasto para una categoría (Comida, Combustible…).
///  • [overallExpense]: límite de todo lo gastado en el mes.
///  • [savings]: meta de ahorro — que el neto (ingresos − gastos) llegue a [amountMinor].
enum BudgetKind { category, overallExpense, savings }

/// Umbral cruzado. Para [BudgetKind.category]/[overallExpense] son malas noticias
/// (te acercas o te pasaste del límite); para [BudgetKind.savings] son buenas
/// (te acercas o llegaste a la meta). Mismo cálculo, distinto tono en el aviso.
enum AlertLevel {
  approaching, // ratio >= 0.8
  reached; // ratio >= 1.0

  double get ratioThreshold => this == approaching ? 0.8 : 1.0;
}

class Budget {
  const Budget({
    required this.id,
    required this.kind,
    required this.amountMinor,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
  });

  final String id;
  final BudgetKind kind;

  /// Sólo para [BudgetKind.category]. Límite (gasto) o meta (ahorro), siempre positivo.
  final int amountMinor;
  final String? categoryId;
  final String? categoryName;
  final String? categoryIcon;

  String get title => switch (kind) {
        BudgetKind.category => categoryName ?? 'Categoría',
        BudgetKind.overallExpense => 'Límite general de gastos',
        BudgetKind.savings => 'Meta de ahorro',
      };

  String get icon => switch (kind) {
        BudgetKind.category => categoryIcon ?? '🏷️',
        BudgetKind.overallExpense => '🚦',
        BudgetKind.savings => '🐷',
      };
}

/// Presupuesto + cuánto llevas este mes.
class BudgetProgress {
  const BudgetProgress({required this.budget, required this.currentMinor});

  final Budget budget;

  /// Gastado (para category/overallExpense) o neto ahorrado (para savings).
  /// Puede ser negativo en `savings` si el mes va en rojo.
  final int currentMinor;

  double get ratio => budget.amountMinor == 0 ? 0 : currentMinor / budget.amountMinor;

  /// Nivel más alto ya alcanzado ahora mismo, o `null` si vas tranquilo (<80%).
  AlertLevel? get level {
    if (ratio >= AlertLevel.reached.ratioThreshold) return AlertLevel.reached;
    if (ratio >= AlertLevel.approaching.ratioThreshold) return AlertLevel.approaching;
    return null;
  }

  bool get isOver => budget.kind != BudgetKind.savings && ratio >= 1.0;
}

/// Clave de período mensual ("2026-09"). Compartida con Kotlin/Swift: no cambiar el formato.
String monthPeriodKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

TxType? expenseTypeFor(BudgetKind kind) => kind == BudgetKind.savings ? null : TxType.expense;
