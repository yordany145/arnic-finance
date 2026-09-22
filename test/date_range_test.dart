import 'package:arnic_finance/domain/date_range.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Miércoles 17 sep 2025, 15:30
  final now = DateTime(2025, 9, 17, 15, 30);

  test('hoy y ayer', () {
    final today = resolveRange(PeriodPreset.today, now)!;
    expect(today.start, DateTime(2025, 9, 17));
    expect(today.endExclusive, DateTime(2025, 9, 18));
    final yesterday = resolveRange(PeriodPreset.yesterday, now)!;
    expect(yesterday.start, DateTime(2025, 9, 16));
    expect(yesterday.endExclusive, DateTime(2025, 9, 17));
  });

  test('semana empieza en lunes', () {
    final week = resolveRange(PeriodPreset.week, now)!;
    expect(week.start, DateTime(2025, 9, 15));
    expect(week.endExclusive, DateTime(2025, 9, 22));
    // Un lunes es el primer día de su propia semana; un domingo, el último.
    expect(resolveRange(PeriodPreset.week, DateTime(2025, 9, 15))!.start, DateTime(2025, 9, 15));
    expect(resolveRange(PeriodPreset.week, DateTime(2025, 9, 21))!.start, DateTime(2025, 9, 15));
  });

  test('mes, incluso diciembre', () {
    final m = resolveRange(PeriodPreset.month, now)!;
    expect(m.start, DateTime(2025, 9));
    expect(m.endExclusive, DateTime(2025, 10));
    expect(resolveRange(PeriodPreset.month, DateTime(2025, 12, 31))!.endExclusive, DateTime(2026, 1));
  });

  test('rango personalizado 15 sep → 14 oct incluye todo el 14 de octubre', () {
    final r = DateRange.days(DateTime(2025, 9, 15), DateTime(2025, 10, 14));
    expect(r.contains(DateTime(2025, 9, 15, 0, 0)), isTrue);
    expect(r.contains(DateTime(2025, 10, 14, 23, 59, 59, 999)), isTrue);
    expect(r.contains(DateTime(2025, 9, 14, 23, 59)), isFalse);
    expect(r.contains(DateTime(2025, 10, 15)), isFalse);
    expect(r.lastDay, DateTime(2025, 10, 14));
  });

  test('todo = sin límite', () {
    expect(resolveRange(PeriodPreset.all, now), isNull);
  });
}
