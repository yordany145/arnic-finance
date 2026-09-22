import 'package:arnic_finance/domain/assistant/text_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalize quita acentos y colapsa espacios', () {
    expect(normalize('¿Cuánto Gasté   Hoy?'), '¿cuanto gaste hoy?');
    expect(normalize('Combustión'), 'combustion');
    expect(normalize('Cañón'), 'cañon');
  });

  test('levenshtein: transposición cuenta como un solo cambio', () {
    expect(levenshtein('comdia', 'comida'), 1);
  });

  test('levenshtein: sustitución simple', () {
    expect(levenshtein('conida', 'comida'), 1);
  });

  test('levenshtein: cadenas iguales', () => expect(levenshtein('comida', 'comida'), 0));

  test('containsWord: palabra completa', () {
    expect(containsWord('gaste en comida hoy', 'comida'), isTrue);
    // Un plural natural ("comidas") debe reconocerse igual: la tolerancia a
    // typos de 1 letra también cubre este caso, y es justamente lo que
    // queremos (es una forma normal de hablar, no un error).
    expect(containsWord('gaste en comidas hoy', 'comida'), isTrue);
    expect(containsWord('gaste en peliculas hoy', 'comida'), isFalse);
  });

  test('containsWord: typo tolerado sólo para palabras de 5+ letras', () {
    expect(containsWord('gaste en comdia hoy', 'comida'), isTrue);
    expect(containsWord('fui al bar', 'ba'), isFalse); // needle corta: no aplica tolerancia
  });

  test('containsWord: nombre de varias palabras es sub-cadena', () {
    expect(containsWord('cuanto tengo en banco popular', 'banco popular'), isTrue);
    expect(containsWord('cuanto tengo en el banco', 'banco popular'), isFalse);
  });
}
