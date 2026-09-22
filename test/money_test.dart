import 'package:arnic_finance/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatMoney', () {
    expect(formatMoney(150000, 'RD\$'), 'RD\$1,500');
    expect(formatMoney(150050, 'RD\$'), 'RD\$1,500.50');
    expect(formatMoney(-50000, 'RD\$', showSign: true), '-RD\$500');
    expect(formatMoney(2500000, 'RD\$', showSign: true), '+RD\$25,000');
    expect(formatMoney(5, 'RD\$'), 'RD\$0.05');
    expect(formatMoney(0, 'RD\$', showSign: true), 'RD\$0');
  });

  test('parseAmountMinor / amountToInputText', () {
    expect(parseAmountMinor('350'), 35000);
    expect(parseAmountMinor('12.5'), 1250);
    expect(parseAmountMinor('7.'), 700);
    expect(parseAmountMinor('0.05'), 5);
    expect(parseAmountMinor(''), 0);
    expect(amountToInputText(35000), '350');
    expect(amountToInputText(1250), '12.5');
    expect(amountToInputText(5), '0.05');
  });

  String type(String keys) => keys.split('').fold('', applyAmountKey);

  test('teclado numérico', () {
    expect(type('350'), '350');
    expect(type('007'), '7');
    expect(type('.5'), '0.5');
    expect(type('1.2.3'), '1.23');
    expect(type('1.234'), '1.23'); // máximo 2 decimales
    expect(type('1234567890'), '123456789'); // máximo 9 enteros
    expect(applyAmountKey('12', '⌫'), '1');
    expect(applyAmountKey('', '⌫'), '');
    expect(applyAmountKey('0', '0'), '0');
  });
}
