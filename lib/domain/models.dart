import 'enums.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.sortOrder,
    this.isDeleted = false,
  });

  final String id;
  final String name;

  /// Emoji. Se eligió emoji (y no un icono de fuente) para que Flutter, Kotlin
  /// y Swift lo muestren igual sin mapear nombres de iconos.
  final String icon;
  final TxType type;
  final int sortOrder;
  final bool isDeleted;
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    required this.sortOrder,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final String icon;
  final AccountKind kind;
  final int sortOrder;
  final bool isDeleted;
}

class Movement {
  const Movement({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.category,
    required this.account,
    required this.occurredAt,
    this.note,
  });

  final String id;
  final TxType type;

  /// Siempre positivo, en unidades menores (centavos). El signo lo da [type].
  final int amountMinor;
  final Category category;
  final Account account;
  final DateTime occurredAt;
  final String? note;

  int get signedMinor => type.isExpense ? -amountMinor : amountMinor;
}

/// Datos para crear o editar un movimiento.
class MovementInput {
  const MovementInput({
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.accountId,
    required this.occurredAt,
    this.note,
  });

  final TxType type;
  final int amountMinor;
  final String categoryId;
  final String accountId;
  final DateTime occurredAt;
  final String? note;
}

class PeriodSummary {
  const PeriodSummary({this.incomeMinor = 0, this.expenseMinor = 0});

  final int incomeMinor;
  final int expenseMinor;
  int get balanceMinor => incomeMinor - expenseMinor;
}
