import 'package:arnic_finance/domain/assistant/period_parser.dart';
import 'package:arnic_finance/domain/date_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Martes 2026-09-22, para que "esta semana" tenga un lunes de referencia claro.
  final now = DateTime(2026, 9, 22, 14, 30);

  test('hoy', () {
    final p = extractPeriod('cuanto gaste hoy', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 22), DateTime(2026, 9, 22)));
    expect(p.label, 'hoy');
  });

  test('ayer', () {
    final p = extractPeriod('cuanto gaste ayer', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 21), DateTime(2026, 9, 21)));
  });

  test('anteayer no se confunde con ayer', () {
    final p = extractPeriod('cuanto gaste anteayer', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 20), DateTime(2026, 9, 20)));
  });

  test('esta semana empieza en lunes', () {
    final p = extractPeriod('cuanto gaste esta semana', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 21), DateTime(2026, 9, 27)));
  });

  test('semana pasada no se confunde con esta semana', () {
    final p = extractPeriod('cuanto gaste la semana pasada', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 14), DateTime(2026, 9, 20)));
  });

  test('este mes', () {
    final p = extractPeriod('cuanto gaste este mes', now)!;
    expect(p.range, DateRange(DateTime(2026, 9), DateTime(2026, 10)));
  });

  test('mes pasado no se confunde con este mes', () {
    final p = extractPeriod('cuanto gaste el mes pasado', now)!;
    expect(p.range, DateRange(DateTime(2026, 8), DateTime(2026, 9)));
  });

  test('mes pasado en enero retrocede al diciembre anterior', () {
    final jan = DateTime(2026, 1, 15);
    final p = extractPeriod('cuanto gaste el mes pasado', jan)!;
    expect(p.range, DateRange(DateTime(2025, 12), DateTime(2026, 1)));
  });

  test('este año', () {
    final p = extractPeriod('cuanto gaste este ano', now)!;
    expect(p.range, DateRange(DateTime(2026, 1), DateTime(2027, 1)));
  });

  test('todo / siempre no tiene límite', () {
    expect(extractPeriod('cuanto he gastado en total', now)!.range, isNull);
    expect(extractPeriod('cuanto he gastado siempre', now)!.range, isNull);
  });

  test('ultimos N dias', () {
    final p = extractPeriod('gastos de los ultimos 7 dias', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 16), DateTime(2026, 9, 22)));
  });

  test('rango explícito del 5 al 20 de septiembre', () {
    final p = extractPeriod('cuanto gaste del 5 al 20 de septiembre', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 5), DateTime(2026, 9, 20)));
  });

  test('rango explícito con meses distintos', () {
    final p = extractPeriod('del 20 de agosto al 5 de septiembre', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 8, 20), DateTime(2026, 9, 5)));
  });

  test('fecha explícita de un solo día', () {
    final p = extractPeriod('cuanto gaste el 15 de septiembre', now)!;
    expect(p.range, DateRange.days(DateTime(2026, 9, 15), DateTime(2026, 9, 15)));
  });

  test('sin ninguna referencia temporal', () {
    expect(extractPeriod('cuanto gaste en comida', now), isNull);
  });

  test('maskSpan borra sólo el tramo reconocido', () {
    final p = extractPeriod('cuanto gaste hoy en comida', now)!;
    final masked = maskSpan('cuanto gaste hoy en comida', p.start, p.end);
    expect(masked, 'cuanto gaste     en comida');
  });
}
