import '../enums.dart';
import 'period_parser.dart';

/// Lo que el usuario quiso decir, ya clasificado y con los datos que se
/// pudieron extraer del texto libre. `AssistantEngine` decide, para cada uno,
/// si le falta algo antes de poder responder.
sealed class AssistantIntent {
  const AssistantIntent();
}

class GreetingIntent extends AssistantIntent {
  const GreetingIntent();
}

class ThanksIntent extends AssistantIntent {
  const ThanksIntent();
}

class HelpIntent extends AssistantIntent {
  const HelpIntent();
}

/// Balance total (todos los ingresos − todos los gastos, sin período).
class BalanceIntent extends AssistantIntent {
  const BalanceIntent();
}

/// "¿Cuánto gasté/ingresé [en <categoría>] [en <cuenta>] [<período>]?"
/// `type == null` significa "ingresos y gastos" (p. ej. "¿cuánto moví esta semana?").
class TotalsIntent extends AssistantIntent {
  const TotalsIntent({this.type, this.period, this.categoryId, this.categoryName, this.accountId, this.accountName});

  final TxType? type;
  final PeriodExtraction? period;
  final String? categoryId;
  final String? categoryName;
  final String? accountId;
  final String? accountName;
}

/// "¿Gasté más este mes que el pasado?"
class CompareIntent extends AssistantIntent {
  const CompareIntent({required this.type, required this.currentLabel, required this.current, required this.previous});

  final TxType type;
  final String currentLabel;
  final PeriodExtraction current;
  final PeriodExtraction previous;
}

class TopCategoriesIntent extends AssistantIntent {
  const TopCategoriesIntent({required this.type, this.period});

  final TxType type;
  final PeriodExtraction? period;
}

class AverageIntent extends AssistantIntent {
  const AverageIntent({required this.type, this.period});

  final TxType type;
  final PeriodExtraction? period;
}

class BudgetsStatusIntent extends AssistantIntent {
  const BudgetsStatusIntent();
}

class AccountsStatusIntent extends AssistantIntent {
  const AccountsStatusIntent();
}

class RecentMovementsIntent extends AssistantIntent {
  const RecentMovementsIntent({this.type});

  final TxType? type;
}

/// Busca movimientos cuya nota contenga [query] (texto libre).
class SearchMovementsIntent extends AssistantIntent {
  const SearchMovementsIntent({required this.query, this.period});

  final String query;
  final PeriodExtraction? period;
}

/// "Gasté 500 en comida" / "cobré 3000 de salario": registra un movimiento desde el chat.
class RegisterMovementIntent extends AssistantIntent {
  const RegisterMovementIntent({
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.categoryName,
    this.accountId,
    this.note,
    this.yesterday = false,
  });

  final TxType type;
  final int amountMinor;
  final String categoryId;
  final String categoryName;
  final String? accountId;
  final String? note;

  /// "gasté 500 ayer": se registra con la fecha de ayer.
  final bool yesterday;
}

enum AlertGoal { categoryLimit, overallLimit, savingsGoal }

/// "Avísame si gasto más de 5000 en Comida" → literalmente un presupuesto de
/// categoría; ver `AssistantEngine` y `docs/ARQUITECTURA.md`.
class CreateAlertIntent extends AssistantIntent {
  const CreateAlertIntent({required this.goal, this.amountMinor, this.categoryId, this.categoryName});

  final AlertGoal goal;
  final int? amountMinor;
  final String? categoryId;
  final String? categoryName;

  CreateAlertIntent copyWith({int? amountMinor, String? categoryId, String? categoryName}) => CreateAlertIntent(
        goal: goal,
        amountMinor: amountMinor ?? this.amountMinor,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName ?? this.categoryName,
      );
}

/// El usuario pidió una alerta que no es un límite de categoría, un límite
/// general de gastos ni una meta de ahorro (las únicas que hoy existen como
/// presupuesto). Se dice claramente en vez de fingir que se configuró algo.
class UnsupportedAlertIntent extends AssistantIntent {
  const UnsupportedAlertIntent(this.reason);

  final String reason;
}

class UnknownIntent extends AssistantIntent {
  const UnknownIntent();
}
