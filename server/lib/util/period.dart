/// `[start, endExclusive)` en epoch-milisegundos.
typedef Range = ({int start, int endExclusive});

/// 'today' | 'yesterday' | 'week' | 'month' | 'all' | null (== 'all').
/// Mismo criterio que `lib/domain/date_range.dart` del lado Flutter (semana
/// empieza en lunes), simplificado a lo que necesita esta API.
Range? resolvePeriodRange(String? period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case null:
    case 'all':
      return null;
    case 'today':
      return (start: today.millisecondsSinceEpoch, endExclusive: today.add(const Duration(days: 1)).millisecondsSinceEpoch);
    case 'yesterday':
      final y = today.subtract(const Duration(days: 1));
      return (start: y.millisecondsSinceEpoch, endExclusive: today.millisecondsSinceEpoch);
    case 'week':
      final offset = (today.weekday - DateTime.monday) % 7;
      final start = today.subtract(Duration(days: offset));
      return (start: start.millisecondsSinceEpoch, endExclusive: start.add(const Duration(days: 7)).millisecondsSinceEpoch);
    case 'month':
      final start = DateTime(now.year, now.month);
      final end = DateTime(now.year, now.month + 1);
      return (start: start.millisecondsSinceEpoch, endExclusive: end.millisecondsSinceEpoch);
    default:
      throw FormatException("period inválido: '$period' (usa today, yesterday, week, month o all).");
  }
}
