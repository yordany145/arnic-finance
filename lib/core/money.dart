import 'package:intl/intl.dart';

final _whole = NumberFormat('#,##0', 'en_US');

const kFallbackCurrencySymbol = 'RD\$';

/// `150000` → `RD$1,500`; `150050` → `RD$1,500.50`.
/// Separadores estilo RD (coma de miles, punto decimal), como en tus ejemplos.
String formatMoney(int minor, String symbol, {bool showSign = false}) {
  final negative = minor < 0;
  final abs = minor.abs();
  final cents = abs % 100;
  final body = '${_whole.format(abs ~/ 100)}${cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}'}';
  final sign = negative ? '-' : (showSign && minor > 0 ? '+' : '');
  return '$sign$symbol$body';
}

/// Convierte el texto del teclado (`"350"`, `"12.5"`, `"7."`) a unidades menores.
int parseAmountMinor(String text) {
  if (text.isEmpty) return 0;
  final parts = text.split('.');
  final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? 0;
  final frac = parts.length > 1 ? parts[1].padRight(2, '0').substring(0, 2) : '00';
  return whole * 100 + (int.tryParse(frac) ?? 0);
}

/// Inverso de [parseAmountMinor], para editar un movimiento existente.
String amountToInputText(int minor) {
  final cents = minor % 100;
  return cents == 0 ? '${minor ~/ 100}' : '${minor ~/ 100}.${cents.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}

/// Reglas del teclado numérico: sin ceros a la izquierda, un solo punto,
/// máximo 2 decimales y 9 dígitos enteros. `key` es un dígito, `.` o `⌫`.
/// (La versión Kotlin de la hoja nativa replica exactamente esto.)
String applyAmountKey(String current, String key) {
  if (key == '⌫') return current.isEmpty ? current : current.substring(0, current.length - 1);
  if (key == '.') {
    if (current.contains('.')) return current;
    return current.isEmpty ? '0.' : '$current.';
  }
  final dot = current.indexOf('.');
  if (dot >= 0) {
    return current.length - dot - 1 >= 2 ? current : current + key;
  }
  if (current == '0') return key == '0' ? current : key;
  return current.length >= 9 ? current : current + key;
}
