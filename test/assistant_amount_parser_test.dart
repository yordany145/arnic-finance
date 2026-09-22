import 'package:arnic_finance/domain/assistant/amount_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entero simple', () => expect(extractAmountMinor('5000'), 500000));
  test('con miles separados por coma', () => expect(extractAmountMinor('5,000'), 500000));
  test('con decimales', () => expect(extractAmountMinor('1500.50'), 150050));
  test('con sufijo k', () => expect(extractAmountMinor('5k'), 500000));
  test('con sufijo mil', () => expect(extractAmountMinor('5 mil'), 500000));
  test('dentro de una frase', () => expect(extractAmountMinor('avisame si gasto mas de 3000 en comida'), 300000));
  test('sin ningún número', () => expect(extractAmountMinor('avisame si gasto mucho'), isNull));
  test('decimal con sufijo mil', () => expect(extractAmountMinor('2.5 mil'), 250000));
}
