/// Busca un monto en texto libre (ya normalizado y, idealmente, con la fecha
/// enmascarada primero por [period_parser] para no confundir un día del mes
/// con un monto). Reconoce miles con coma y decimales con punto (igual que
/// `core/money.dart`), y el sufijo `k`/`mil` como multiplicador
/// ("5k" o "5 mil" → 5000).
///
/// Devuelve el monto en unidades menores (centavos), o `null` si no hay
/// ningún número reconocible.
int? extractAmountMinor(String text) {
  final match = RegExp(r'(\d{1,3}(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*(mil|k)?\b').firstMatch(text);
  if (match == null) return null;
  final numberText = match.group(1)!.replaceAll(',', '');
  final value = double.tryParse(numberText);
  if (value == null) return null;
  final multiplier = match.group(2) != null ? 1000 : 1;
  return (value * multiplier * 100).round();
}
