import 'package:arnic_finance/domain/month_pace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sin gastos no hay ritmo', () => expect(computeMonthPace(spentMinor: 0, now: DateTime(2026, 10, 9)), isNull));

  test('promedio diario y proyección al cierre (octubre: 31 días)', () {
    final p = computeMonthPace(spentMinor: 900000, now: DateTime(2026, 10, 9))!;
    expect(p.dailyAverageMinor, 100000);
    expect(p.projectedMinor, 3100000);
    expect(p.daysLeft, 22);
    expect(p.projectionReliable, isTrue);
    expect(p.perDayLeftMinor, isNull);
    expect(p.projectedOverLimit, isFalse);
  });

  test('con límite general: cuánto queda por día y si la proyección lo supera', () {
    final p = computeMonthPace(spentMinor: 900000, now: DateTime(2026, 10, 9), limitMinor: 2000000)!;
    expect(p.perDayLeftMinor, 50000); // 1,100,000 / 22 días
    expect(p.projectedOverLimit, isTrue);
  });

  test('límite ya superado: no hay "por día" y se marca', () {
    final p = computeMonthPace(spentMinor: 900000, now: DateTime(2026, 10, 9), limitMinor: 800000)!;
    expect(p.perDayLeftMinor, isNull);
    expect(p.projectedOverLimit, isTrue);
  });

  test('los primeros días la proyección no es confiable; el último día no divide por cero', () {
    expect(computeMonthPace(spentMinor: 1000, now: DateTime(2026, 10, 2))!.projectionReliable, isFalse);
    final last = computeMonthPace(spentMinor: 1000, now: DateTime(2026, 10, 31), limitMinor: 5000)!;
    expect(last.daysLeft, 0);
    expect(last.perDayLeftMinor, 4000);
  });

  test('febrero bisiesto/no bisiesto', () {
    expect(computeMonthPace(spentMinor: 100, now: DateTime(2028, 2, 10))!.daysInMonth, 29);
    expect(computeMonthPace(spentMinor: 100, now: DateTime(2026, 2, 10))!.daysInMonth, 28);
  });
}
