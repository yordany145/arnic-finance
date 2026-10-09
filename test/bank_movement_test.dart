import 'package:arnic_finance/domain/bank_movement.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const food = Category(id: 'exp_food', name: 'Comida', icon: '🍔', type: TxType.expense, sortOrder: 0);
  const other = Category(id: 'exp_other', name: 'Otros', icon: '📦', type: TxType.expense, sortOrder: 1);
  const card = Account(id: 'a', name: 'Tarjeta BHD', icon: '💳', kind: AccountKind.creditCard, sortOrder: 0);

  Movement mov({String? note, Category category = other, TxType type = TxType.expense, String id = 'm1'}) =>
      Movement(id: id, type: type, amountMinor: 100, category: category, account: card, occurredAt: DateTime(2026, 10, 9), note: note);

  test('reconoce el sufijo (tarjeta ••1234) que pone el puente', () {
    final m = mov(note: 'AMAZON 1 (tarjeta ••8866)');
    expect(isBankMovement(m), isTrue);
    expect(bankMerchant(m), 'AMAZON 1');
  });

  test('una nota escrita a mano no es del banco', () {
    expect(isBankMovement(mov(note: 'almuerzo con Juan')), isFalse);
    expect(isBankMovement(mov(note: null)), isFalse);
    expect(bankMerchant(mov(note: 'almuerzo')), isNull);
  });

  test('un ingreso nunca se marca como del banco', () {
    expect(isBankMovement(mov(note: 'X (tarjeta ••1234)', type: TxType.income)), isFalse);
  });

  test('por revisar: del banco + en Otros + sin confirmar', () {
    final m = mov(note: 'COMERCIO RARO (tarjeta ••2110)');
    expect(needsReview(m, const {}), isTrue);
    expect(needsReview(m, {'m1'}), isFalse, reason: 'ya confirmado');
    expect(needsReview(mov(note: 'X (tarjeta ••2110)', category: food), const {}), isFalse, reason: 'ya tiene categoría');
    expect(needsReview(mov(note: 'a mano'), const {}), isFalse, reason: 'no es del banco');
  });
}
