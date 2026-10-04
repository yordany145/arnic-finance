import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:arnic_finance/domain/report.dart';
import 'package:flutter_test/flutter_test.dart';

Category _cat(String id, String name) => Category(id: id, name: name, icon: '🏷️', type: TxType.expense, sortOrder: 0);
const _acc = Account(id: 'a', name: 'Efectivo', icon: '💵', kind: AccountKind.cash, sortOrder: 0);

Movement _m(TxType type, int minor, Category c, DateTime at) =>
    Movement(id: '${at.microsecondsSinceEpoch}$minor', type: type, amountMinor: minor, category: c, account: _acc, occurredAt: at);

void main() {
  final food = _cat('f', 'Comida');
  final fuel = _cat('g', 'Combustible');
  final now = DateTime(2026, 10, 20);
  final movements = [
    _m(TxType.expense, 100000, food, DateTime(2026, 10, 3)),
    _m(TxType.expense, 250000, fuel, DateTime(2026, 10, 9)),
    _m(TxType.expense, 50000, food, DateTime(2026, 10, 31, 23, 59)), // último minuto del mes: sigue siendo octubre
    _m(TxType.income, 3000000, _cat('s', 'Salario'), DateTime(2026, 10, 1)),
    _m(TxType.expense, 999900, food, DateTime(2026, 9, 30, 23, 59)),
  ];

  test('monthlyTotals: 6 meses terminando en el actual, con ceros en los vacíos', () {
    final totals = monthlyTotals(movements, now);
    expect(totals.length, 6);
    expect(totals.first.month, DateTime(2026, 5));
    expect(totals.last.month, DateTime(2026, 10));
    expect(totals.last.expenseMinor, 400000);
    expect(totals.last.incomeMinor, 3000000);
    expect(totals.last.netMinor, 2600000);
    expect(totals[4].expenseMinor, 999900); // septiembre
    expect(totals[0].expenseMinor, 0);
  });

  test('monthlyTotals cruza el año correctamente', () {
    final totals = monthlyTotals(const [], DateTime(2026, 2, 10));
    expect(totals.map((t) => '${t.month.year}-${t.month.month}').toList(), ['2025-9', '2025-10', '2025-11', '2025-12', '2026-1', '2026-2']);
  });

  test('expenseByCategory: solo gastos del mes, de mayor a menor', () {
    final byCat = expenseByCategory(movements, DateTime(2026, 10, 15));
    expect(byCat.map((c) => (c.category.name, c.minor)).toList(), [('Combustible', 250000), ('Comida', 150000)]);
    expect(expenseByCategory(movements, DateTime(2026, 8)), isEmpty);
  });
}
