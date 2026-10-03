const validAccountKinds = {'cash', 'bank', 'creditCard', 'savings', 'checking'};
const validTxTypes = {'expense', 'income'};
const validBudgetKinds = {'category', 'overallExpense', 'savings'};

// Debe coincidir con ../../../lib/domain/assistant/text_normalize.dart
// (mismo propósito: reconocer el nombre de una categoría escrito a mano,
// aquí por quien llama a la API en vez de por el usuario en el chat).
const _accented = 'áéíóúÁÉÍÓÚüÜ';
const _plain = 'aeiouAEIOUuU';

String normalize(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final i = _accented.indexOf(char);
    buffer.write(i >= 0 ? _plain[i] : char);
  }
  return buffer.toString().toLowerCase().trim();
}
