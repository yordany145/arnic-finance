/// Tipo de movimiento. Los nombres (`expense`/`income`) se guardan tal cual en
/// SQLite y los usa también el código nativo (Kotlin/Swift): no renombrar.
enum TxType {
  expense,
  income;

  bool get isExpense => this == TxType.expense;
  String get label => isExpense ? 'Gasto' : 'Ingreso';
  String get pluralLabel => isExpense ? 'Gastos' : 'Ingresos';
}

enum AccountKind {
  cash('Efectivo', '💵'),
  bank('Banco', '🏦'),
  creditCard('Tarjeta de crédito', '💳'),
  savings('Cuenta de ahorro', '🐖'),
  checking('Cuenta corriente', '🧾');

  const AccountKind(this.label, this.defaultIcon);
  final String label;
  final String defaultIcon;
}

enum PeriodPreset {
  today('Hoy'),
  yesterday('Ayer'),
  week('Esta semana'),
  month('Este mes'),
  custom('Rango'),
  all('Todo');

  const PeriodPreset(this.label);
  final String label;
}
