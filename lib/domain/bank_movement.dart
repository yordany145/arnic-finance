import 'models.dart';

/// El puente de correo anota cada consumo de tarjeta como "COMERCIO (tarjeta ••1234)".
/// Es la única huella de que un gasto entró solo desde un aviso del banco (no hay columna
/// propia a propósito: la tabla es contrato con el código nativo y el servidor).
final _bankNote = RegExp(r'\(tarjeta ••\d{4}\)\s*$');

bool isBankMovement(Movement m) => m.type.isExpense && _bankNote.hasMatch(m.note ?? '');

/// Comercio sin el sufijo de tarjeta ("AMAZON 1 (tarjeta ••8866)" → "AMAZON 1").
String? bankMerchant(Movement m) => isBankMovement(m) ? m.note!.replaceFirst(_bankNote, '').trim() : null;

bool _isOther(Category c) => c.id == 'exp_other' || c.name.trim().toLowerCase() == 'otros';

/// Gasto del banco que quedó sin clasificar y que el usuario todavía no confirmó.
bool needsReview(Movement m, Set<String> reviewedIds) => isBankMovement(m) && _isOther(m.category) && !reviewedIds.contains(m.id);
