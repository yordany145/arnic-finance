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

/// Valida la configuración de usuario. Devuelve el mensaje de error, o `null` si es válida.
/// Forma esperada (todo opcional):
/// `{"cards": [{"accountId": "...", "limitMinor": 1500000, "cutDay": 15, "dueDay": 5}]}`
/// `cutDay`/`dueDay` pueden ser `null` (sin configurar) o 1–31.
String? validateUserConfig(Map<String, dynamic> config) {
  final cards = config['cards'];
  if (cards == null) return null;
  if (cards is! List) return '"cards" debe ser una lista.';
  if (cards.length > 50) return 'Demasiadas tarjetas.';
  final seen = <String>{};
  for (final card in cards) {
    if (card is! Map<String, dynamic>) return 'Cada tarjeta debe ser un objeto.';
    final id = card['accountId'];
    if (id is! String || id.isEmpty) return 'Cada tarjeta necesita "accountId".';
    if (!seen.add(id)) return 'Tarjeta repetida: $id.';
    final limit = card['limitMinor'];
    if (limit != null && (limit is! int || limit < 0 || limit > 100000000000)) return '"limitMinor" debe ser un entero >= 0.';
    for (final key in const ['cutDay', 'dueDay']) {
      final day = card[key];
      if (day != null && (day is! int || day < 1 || day > 31)) return '"$key" debe ser un día entre 1 y 31.';
    }
  }
  return null;
}
