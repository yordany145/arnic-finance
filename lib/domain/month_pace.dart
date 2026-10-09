/// Ritmo de gasto del mes en curso: promedio diario, proyección al cierre y, si hay un límite
/// general, cuánto se puede gastar por día hasta fin de mes.
class MonthPace {
  const MonthPace({
    required this.spentMinor,
    required this.dayOfMonth,
    required this.daysInMonth,
    required this.dailyAverageMinor,
    required this.projectedMinor,
    this.limitMinor,
    this.perDayLeftMinor,
  });

  final int spentMinor;
  final int dayOfMonth;
  final int daysInMonth;
  final int dailyAverageMinor;
  final int projectedMinor;
  final int? limitMinor;

  /// Lo que queda del límite repartido entre los días que faltan; `null` sin límite o si ya se pasó.
  final int? perDayLeftMinor;

  int get daysLeft => daysInMonth - dayOfMonth;

  /// La proyección con 1–2 días de datos es puro ruido: no se muestra.
  bool get projectionReliable => dayOfMonth >= 3;

  bool get projectedOverLimit => limitMinor != null && projectedMinor > limitMinor!;
}

/// `null` si todavía no hay gastos este mes.
MonthPace? computeMonthPace({required int spentMinor, required DateTime now, int? limitMinor}) {
  if (spentMinor <= 0) return null;
  final day = now.day;
  final days = DateTime(now.year, now.month + 1, 0).day;
  final daysLeft = days - day;
  final remaining = limitMinor == null ? null : limitMinor - spentMinor;
  return MonthPace(
    spentMinor: spentMinor,
    dayOfMonth: day,
    daysInMonth: days,
    dailyAverageMinor: (spentMinor / day).round(),
    projectedMinor: (spentMinor * days / day).round(),
    limitMinor: limitMinor,
    perDayLeftMinor: remaining == null || remaining <= 0 ? null : (remaining / (daysLeft < 1 ? 1 : daysLeft)).floor(),
  );
}
