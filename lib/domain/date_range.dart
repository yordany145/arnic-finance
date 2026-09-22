import 'enums.dart';

/// Intervalo semiabierto `[start, endExclusive)` en hora local.
///
/// Se usa "fin exclusivo" para que un rango de calendario "15 sep → 14 oct"
/// incluya todo el 14 de octubre (hasta las 23:59:59.999) sin trucos.
class DateRange {
  const DateRange(this.start, this.endExclusive);

  /// Rango de días de calendario, ambos extremos inclusivos.
  factory DateRange.days(DateTime firstDay, DateTime lastDay) {
    final start = DateTime(firstDay.year, firstDay.month, firstDay.day);
    // `DateTime(y, m, d + 1)` respeta cambios de horario (no suma 24 h fijas).
    final end = DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
    return DateRange(start, end);
  }

  final DateTime start;
  final DateTime endExclusive;

  /// Último día incluido (para mostrarlo al usuario).
  DateTime get lastDay => DateTime(endExclusive.year, endExclusive.month, endExclusive.day - 1);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(endExclusive);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(start, endExclusive);
}

/// La semana empieza el lunes (ISO 8601).
const int kFirstWeekday = DateTime.monday;

/// Resuelve un preset a un rango concreto. `null` significa "sin límite".
DateRange? resolveRange(PeriodPreset preset, DateTime now, {DateRange? custom}) {
  final today = DateTime(now.year, now.month, now.day);
  switch (preset) {
    case PeriodPreset.today:
      return DateRange.days(today, today);
    case PeriodPreset.yesterday:
      final y = DateTime(today.year, today.month, today.day - 1);
      return DateRange.days(y, y);
    case PeriodPreset.week:
      final offset = (today.weekday - kFirstWeekday) % 7;
      final first = DateTime(today.year, today.month, today.day - offset);
      final last = DateTime(first.year, first.month, first.day + 6);
      return DateRange.days(first, last);
    case PeriodPreset.month:
      return DateRange(DateTime(today.year, today.month), DateTime(today.year, today.month + 1));
    case PeriodPreset.custom:
      return custom;
    case PeriodPreset.all:
      return null;
  }
}
