import '../date_range.dart';

/// Resultado de buscar una referencia temporal dentro de un mensaje.
class PeriodExtraction {
  const PeriodExtraction({required this.range, required this.label, required this.start, required this.end});

  /// `null` = sin límite ("todo", "siempre").
  final DateRange? range;

  /// Para mostrarlo de vuelta al usuario ("este mes", "el 15 de septiembre").
  final String label;

  /// Tramo `[start, end)` del texto YA NORMALIZADO que se reconoció como
  /// fecha, para poder "taparlo" antes de buscar monto/categoría y evitar que
  /// un día de mes se confunda con un monto.
  final int start;
  final int end;
}

const _months = <String, int>{
  'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5, 'junio': 6,
  'julio': 7, 'agosto': 8, 'septiembre': 9, 'setiembre': 9, 'octubre': 10,
  'noviembre': 11, 'diciembre': 12,
};

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Busca una referencia temporal en [text] (ya normalizado: minúsculas, sin
/// acentos). Revisa patrones de más a menos específicos para que "mes pasado"
/// no se confunda con "mes", ni "esta semana" con "semana pasada".
PeriodExtraction? extractPeriod(String text, DateTime now) {
  final today = _day(now);

  // 1) Rango explícito: "del 5 al 20 de septiembre", "del 1 de agosto al 15 de
  //    septiembre", "entre el 5 y el 20 de octubre".
  final rangeMatch = RegExp(
    r'(?:del|desde|entre)\s+(?:el\s+)?(\d{1,2})(?:\s+de\s+(\w+))?\s+(?:al|hasta|y)\s+(?:el\s+)?(\d{1,2})\s+de\s+(\w+)',
  ).firstMatch(text);
  if (rangeMatch != null) {
    final endMonth = _months[rangeMatch.group(4)!];
    if (endMonth != null) {
      final startMonth = rangeMatch.group(2) != null ? _months[rangeMatch.group(2)] : endMonth;
      final startDay = int.parse(rangeMatch.group(1)!);
      final endDay = int.parse(rangeMatch.group(3)!);
      if (startMonth != null && startDay >= 1 && startDay <= 31 && endDay >= 1 && endDay <= 31) {
        final start = DateTime(now.year, startMonth, startDay);
        final end = DateTime(now.year, endMonth, endDay);
        if (!end.isBefore(start)) {
          return PeriodExtraction(
            range: DateRange.days(start, end),
            label: '${rangeMatch.group(1)}${rangeMatch.group(2) != null ? ' de ${rangeMatch.group(2)}' : ''} al ${rangeMatch.group(3)} de ${rangeMatch.group(4)}',
            start: rangeMatch.start,
            end: rangeMatch.end,
          );
        }
      }
    }
  }

  // 2) Fecha explícita de un solo día: "el 15 de septiembre".
  final singleDate = RegExp(r'(?:el\s+)?(\d{1,2})\s+de\s+(\w+)').firstMatch(text);
  if (singleDate != null) {
    final month = _months[singleDate.group(2)!];
    final day = int.tryParse(singleDate.group(1)!);
    if (month != null && day != null && day >= 1 && day <= 31) {
      final d = DateTime(now.year, month, day);
      return PeriodExtraction(
        range: DateRange.days(d, d),
        label: 'el ${singleDate.group(1)} de ${singleDate.group(2)}',
        start: singleDate.start,
        end: singleDate.end,
      );
    }
  }

  // 3) "los últimos N días/semanas".
  final lastN = RegExp(r'ultim[oa]s?\s+(\d{1,3})\s+(dia|dias|semana|semanas)').firstMatch(text);
  if (lastN != null) {
    final n = int.parse(lastN.group(1)!);
    final isWeeks = lastN.group(2)!.startsWith('semana');
    final days = isWeeks ? n * 7 : n;
    final start = today.subtract(Duration(days: days - 1));
    return PeriodExtraction(
      range: DateRange.days(start, today),
      label: 'los últimos $n ${isWeeks ? (n == 1 ? 'semana' : 'semanas') : (n == 1 ? 'día' : 'días')}',
      start: lastN.start,
      end: lastN.end,
    );
  }

  // 4) Palabras relativas, de más a menos específicas.
  final keywordMatchers = <(RegExp, PeriodExtraction Function(RegExpMatch)) >[
    (RegExp(r'antier|anteayer'), (m) {
      final d = today.subtract(const Duration(days: 2));
      return PeriodExtraction(range: DateRange.days(d, d), label: 'anteayer', start: m.start, end: m.end);
    }),
    (RegExp(r'\bayer\b'), (m) {
      final d = today.subtract(const Duration(days: 1));
      return PeriodExtraction(range: DateRange.days(d, d), label: 'ayer', start: m.start, end: m.end);
    }),
    (RegExp(r'\bhoy\b'), (m) =>
        PeriodExtraction(range: DateRange.days(today, today), label: 'hoy', start: m.start, end: m.end)),
    (RegExp(r'semana pasada|la semana anterior'), (m) {
      final offset = (today.weekday - DateTime.monday) % 7;
      final thisWeekStart = today.subtract(Duration(days: offset));
      final start = thisWeekStart.subtract(const Duration(days: 7));
      final end = thisWeekStart.subtract(const Duration(days: 1));
      return PeriodExtraction(range: DateRange.days(start, end), label: 'la semana pasada', start: m.start, end: m.end);
    }),
    (RegExp(r'esta semana|\bsemana\b'), (m) {
      final offset = (today.weekday - DateTime.monday) % 7;
      final start = today.subtract(Duration(days: offset));
      final end = start.add(const Duration(days: 6));
      return PeriodExtraction(range: DateRange.days(start, end), label: 'esta semana', start: m.start, end: m.end);
    }),
    (RegExp(r'mes pasado|el mes anterior'), (m) {
      final start = DateTime(today.year, today.month - 1);
      final end = DateTime(today.year, today.month);
      return PeriodExtraction(range: DateRange(start, end), label: 'el mes pasado', start: m.start, end: m.end);
    }),
    (RegExp(r'este mes|\bmes\b'), (m) {
      final start = DateTime(today.year, today.month);
      final end = DateTime(today.year, today.month + 1);
      return PeriodExtraction(range: DateRange(start, end), label: 'este mes', start: m.start, end: m.end);
    }),
    (RegExp(r'año pasado|el año anterior'), (m) {
      final start = DateTime(today.year - 1, 1);
      final end = DateTime(today.year, 1);
      return PeriodExtraction(range: DateRange(start, end), label: 'el año pasado', start: m.start, end: m.end);
    }),
    (RegExp(r'este año|\bano\b'), (m) {
      final start = DateTime(today.year, 1);
      final end = DateTime(today.year + 1, 1);
      return PeriodExtraction(range: DateRange(start, end), label: 'este año', start: m.start, end: m.end);
    }),
    (RegExp(r'\btodo\b|siempre|en total|historico'), (m) =>
        PeriodExtraction(range: null, label: 'siempre', start: m.start, end: m.end)),
  ];
  for (final (pattern, build) in keywordMatchers) {
    final m = pattern.firstMatch(text);
    if (m != null) return build(m);
  }

  // 5) Sólo un nombre de mes suelto: "en septiembre", "de septiembre".
  final monthOnly = RegExp(r'\b(en|de)\s+(${_monthsPattern})\b'.replaceAll(r'${_monthsPattern}', _months.keys.join('|')))
      .firstMatch(text);
  if (monthOnly != null) {
    final month = _months[monthOnly.group(2)!]!;
    final start = DateTime(now.year, month);
    final end = DateTime(now.year, month + 1);
    return PeriodExtraction(range: DateRange(start, end), label: monthOnly.group(2)!, start: monthOnly.start, end: monthOnly.end);
  }

  return null;
}

/// Quita el tramo reconocido como fecha, para que el resto del análisis
/// (monto, categoría) no lo confunda con otra cosa.
String maskSpan(String text, int start, int end) => text.replaceRange(start, end, ' ' * (end - start));
