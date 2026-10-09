import '../../core/date_labels.dart';
import '../../core/money.dart';
import '../budget.dart';
import '../models.dart';
import '../repositories.dart';
import 'assistant_intent.dart';
import 'period_parser.dart';
import 'text_normalize.dart';

/// Lo que falta para completar una intención a medias (p. ej. una alerta sin
/// monto todavía). La pantalla de chat lo guarda y, en el siguiente mensaje,
/// intenta rellenar sólo ese dato antes de volver a interpretar todo desde cero.
class PendingClarification {
  const PendingClarification({required this.missing, required this.template});

  /// 'amount' | 'category'.
  final String missing;
  final CreateAlertIntent template;
}

class AssistantAnswer {
  const AssistantAnswer(this.text, {this.pending, this.registeredId});

  final String text;
  final PendingClarification? pending;

  /// Si la respuesta registró un movimiento, su id (la pantalla lo usa para "deshacer").
  final String? registeredId;
}

/// Responde una [AssistantIntent] ya clasificada, consultando los datos
/// reales a través de los mismos repositorios que usa el resto de la app
/// (nunca duplica lógica de negocio: reutiliza `MovementRepository`,
/// `BudgetRepository`, etc.)
class AssistantEngine {
  // Posicional (como BudgetAlertService), no nombrado: los 5 tipos son
  // distintos entre sí, así que un orden equivocado ya lo atrapa el compilador.
  AssistantEngine(this._movements, this._accounts, this._budgets, this._currency, this._now, {this._defaultAccountId});

  final MovementRepository _movements;
  final AccountRepository _accounts;
  final BudgetRepository _budgets;
  final String _currency;
  final DateTime _now;
  final String? _defaultAccountId;

  String _money(int minor, {bool showSign = false}) => formatMoney(minor, _currency, showSign: showSign);

  Future<AssistantAnswer> answer(AssistantIntent intent) async {
    return switch (intent) {
      GreetingIntent() => const AssistantAnswer('¡Hola! Pregúntame lo que quieras sobre tus finanzas, por ejemplo "¿cuánto gasté este mes?".'),
      ThanksIntent() => const AssistantAnswer('¡De nada! Aquí ando si necesitas algo más.'),
      HelpIntent() => AssistantAnswer(_helpText),
      BalanceIntent() => _balance(),
      TotalsIntent() => _totals(intent),
      CompareIntent() => _compare(intent),
      TopCategoriesIntent() => _topCategories(intent),
      AverageIntent() => _average(intent),
      BudgetsStatusIntent() => _budgetsStatus(),
      AccountsStatusIntent() => _accountsStatus(),
      RecentMovementsIntent() => _recentMovements(intent),
      SearchMovementsIntent() => _searchMovements(intent),
      RegisterMovementIntent() => _register(intent),
      CreateAlertIntent() => _handleCreateAlert(intent),
      UnsupportedAlertIntent() => AssistantAnswer(intent.reason),
      UnknownIntent() => AssistantAnswer(_unknownText),
    };
  }

  Future<AssistantAnswer> _register(RegisterMovementIntent intent) async {
    final accounts = await _accounts.watch().first;
    if (accounts.isEmpty) return const AssistantAnswer('No tienes ninguna cuenta donde registrarlo. Crea una en Ajustes > Cuentas.');
    final account = accounts.where((a) => a.id == (intent.accountId ?? _defaultAccountId)).firstOrNull ?? accounts.first;
    final when = intent.yesterday ? _now.subtract(const Duration(days: 1)) : _now;
    final id = await _movements.add(MovementInput(
      type: intent.type,
      amountMinor: intent.amountMinor,
      categoryId: intent.categoryId,
      accountId: account.id,
      occurredAt: when,
      note: intent.note,
    ));
    final what = intent.type.isExpense ? 'Gasto' : 'Ingreso';
    final note = intent.note == null ? '' : ' (${intent.note})';
    return AssistantAnswer(
      'Listo: $what de ${_money(intent.amountMinor)} en ${intent.categoryName}$note, cuenta ${account.name}'
      '${intent.yesterday ? ', de ayer' : ''}. Escribe "deshacer" si te equivocaste.',
      registeredId: id,
    );
  }

  Future<AssistantAnswer> _balance() async {
    final s = await _movements.watchSummary(const MovementFilter()).first;
    return AssistantAnswer('Tu balance actual es ${_money(s.balanceMinor, showSign: true)}.');
  }

  Future<AssistantAnswer> _totals(TotalsIntent intent) async {
    final filter = MovementFilter(
      type: intent.type,
      categoryId: intent.categoryId,
      accountId: intent.accountId,
      range: intent.period?.range,
    );
    final s = await _movements.watchSummary(filter).first;
    final periodLabel = intent.period?.label ?? 'en todo el historial';
    final scope = [
      if (intent.categoryName != null) 'en ${intent.categoryName}',
      if (intent.accountName != null) 'desde ${intent.accountName}',
    ].join(' ');
    final scopeText = scope.isEmpty ? '' : ' $scope';

    if (intent.type == null) {
      return AssistantAnswer(
        'En $periodLabel$scopeText tuviste ${_money(s.incomeMinor)} de ingresos y ${_money(s.expenseMinor)} de gastos '
        '(neto ${_money(s.balanceMinor, showSign: true)}).',
      );
    }
    final amount = intent.type!.isExpense ? s.expenseMinor : s.incomeMinor;
    final verb = intent.type!.isExpense ? 'gastaste' : 'ingresaste';
    if (amount == 0) {
      return AssistantAnswer('No registraste ${intent.type!.pluralLabel.toLowerCase()}$scopeText en $periodLabel.');
    }
    final capitalizedPeriod = periodLabel.isEmpty ? periodLabel : periodLabel[0].toUpperCase() + periodLabel.substring(1);
    return AssistantAnswer('$capitalizedPeriod$scopeText $verb ${_money(amount)}.');
  }

  Future<AssistantAnswer> _compare(CompareIntent intent) async {
    final cur = await _movements.watchSummary(MovementFilter(range: intent.current.range)).first;
    final prev = await _movements.watchSummary(MovementFilter(range: intent.previous.range)).first;
    final curAmount = intent.type.isExpense ? cur.expenseMinor : cur.incomeMinor;
    final prevAmount = intent.type.isExpense ? prev.expenseMinor : prev.incomeMinor;
    final verb = intent.type.isExpense ? 'gastado' : 'ingresado';

    if (prevAmount == 0) {
      return AssistantAnswer('En ${intent.currentLabel} llevas ${_money(curAmount)} de ${intent.type.pluralLabel.toLowerCase()}. '
          'En el período anterior no habías $verb nada, así que no hay con qué comparar.');
    }
    final diff = curAmount - prevAmount;
    final pct = (diff.abs() * 100 / prevAmount).round();
    final more = diff > 0;
    final same = diff == 0;
    final verdict = same ? 'exactamente lo mismo' : '${more ? 'más' : 'menos'} ($pct%)';
    return AssistantAnswer(
      'En ${intent.currentLabel} llevas $verb ${_money(curAmount)}, frente a ${_money(prevAmount)} del período anterior: '
      '$verdict.',
    );
  }

  Future<AssistantAnswer> _topCategories(TopCategoriesIntent intent) async {
    final list = await _movements.watch(MovementFilter(type: intent.type, range: intent.period?.range)).first;
    if (list.isEmpty) {
      return AssistantAnswer('No hay ${intent.type.pluralLabel.toLowerCase()} registrados ${intent.period?.label ?? 'todavía'}.');
    }
    final totals = <String, int>{};
    final labels = <String, String>{};
    for (final m in list) {
      totals[m.category.id] = (totals[m.category.id] ?? 0) + m.amountMinor;
      labels[m.category.id] = '${m.category.icon} ${m.category.name}';
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lines = sorted.take(5).map((e) => '${labels[e.key]}: ${_money(e.value)}').join('\n');
    return AssistantAnswer('Tus ${intent.type.pluralLabel.toLowerCase()} ${intent.period?.label ?? 'de siempre'} por categoría:\n$lines');
  }

  Future<AssistantAnswer> _average(AverageIntent intent) async {
    final period = intent.period ?? extractPeriod('este mes', _now)!;
    final range = period.range;
    final s = await _movements.watchSummary(MovementFilter(type: intent.type, range: range)).first;
    final amount = intent.type.isExpense ? s.expenseMinor : s.incomeMinor;

    int days;
    if (range == null) {
      days = 1;
    } else {
      final elapsedEnd = _now.isBefore(range.endExclusive) ? _now : range.endExclusive.subtract(const Duration(milliseconds: 1));
      days = elapsedEnd.difference(range.start).inDays + 1;
      if (days < 1) days = 1;
    }
    final avg = (amount / days).round();
    return AssistantAnswer('En promedio ${intent.type.isExpense ? 'gastas' : 'ingresas'} ${_money(avg)} por día ${period.label} (sobre $days día${days == 1 ? '' : 's'}).');
  }

  Future<AssistantAnswer> _budgetsStatus() async {
    final list = await _budgets.watchProgress(_now).first;
    if (list.isEmpty) {
      return const AssistantAnswer(
        'No tienes presupuestos todavía. Puedo crear uno si me dices algo como "avísame si gasto más de 5000 en Comida".',
      );
    }
    final lines = list.map((p) {
      final pct = (p.ratio * 100).round();
      final status = p.isOver
          ? ' — te pasaste'
          : p.level == AlertLevel.approaching
              ? ' — cerca del límite'
              : (p.budget.kind == BudgetKind.savings && p.ratio >= 1.0)
                  ? ' — ¡meta cumplida!'
                  : '';
      return '${p.budget.icon} ${p.budget.title}: ${_money(p.currentMinor)} de ${_money(p.budget.amountMinor)} ($pct%)$status';
    }).join('\n');
    return AssistantAnswer('Así van tus presupuestos este mes:\n$lines');
  }

  Future<AssistantAnswer> _accountsStatus() async {
    final list = await _accounts.watch().first;
    if (list.isEmpty) return const AssistantAnswer('No tienes cuentas configuradas.');
    final lines = <String>[];
    for (final a in list) {
      final s = await _movements.watchSummary(MovementFilter(accountId: a.id)).first;
      lines.add('${a.icon} ${a.name}: ${_money(s.balanceMinor)}');
    }
    return AssistantAnswer('Tu saldo por cuenta:\n${lines.join('\n')}');
  }

  Future<AssistantAnswer> _recentMovements(RecentMovementsIntent intent) async {
    final list = await _movements.watch(MovementFilter(type: intent.type, limit: 5)).first;
    if (list.isEmpty) return const AssistantAnswer('No hay movimientos registrados todavía.');
    final lines = list
        .map((m) => '${m.category.icon} ${m.category.name}: ${_money(m.signedMinor, showSign: true)} · ${dateTimeLabel(m.occurredAt, _now)}')
        .join('\n');
    return AssistantAnswer('Tus últimos movimientos:\n$lines');
  }

  Future<AssistantAnswer> _searchMovements(SearchMovementsIntent intent) async {
    final normalizedQuery = normalize(intent.query);
    final list = await _movements.watch(MovementFilter(range: intent.period?.range, noteQuery: normalizedQuery, limit: 10)).first;
    if (list.isEmpty) {
      return AssistantAnswer('No encontré movimientos con "${intent.query}"${intent.period == null ? '' : ' ${intent.period!.label}'}.');
    }
    final total = list.fold<int>(0, (sum, m) => sum + m.signedMinor);
    final lines = list
        .map((m) => '${m.category.icon} ${m.category.name}: ${_money(m.signedMinor, showSign: true)} · ${dateTimeLabel(m.occurredAt, _now)} — "${m.note}"')
        .join('\n');
    return AssistantAnswer('Encontré ${list.length} movimiento(s) con "${intent.query}" (total ${_money(total, showSign: true)}):\n$lines');
  }

  /// Crea o actualiza literalmente un presupuesto (ver `docs/ARQUITECTURA.md`
  /// sobre por qué una alerta personalizada ES un presupuesto). Si falta el
  /// monto o la categoría, pide ese único dato y recuerda el resto.
  Future<AssistantAnswer> _handleCreateAlert(CreateAlertIntent intent) async {
    if (intent.goal == AlertGoal.categoryLimit && intent.categoryId == null) {
      return AssistantAnswer(
        '¿Para qué categoría? (dime sólo el nombre, por ejemplo "Comida")',
        pending: PendingClarification(missing: 'category', template: intent),
      );
    }
    if (intent.amountMinor == null || intent.amountMinor! <= 0) {
      return AssistantAnswer(
        '¿Cuál es el monto del límite? (dime sólo el número, por ejemplo "5000")',
        pending: PendingClarification(missing: 'amount', template: intent),
      );
    }

    final existing = await _budgets.watch().first;
    final amount = intent.amountMinor!;
    switch (intent.goal) {
      case AlertGoal.categoryLimit:
        final match = existing.where((b) => b.kind == BudgetKind.category && b.categoryId == intent.categoryId).firstOrNull;
        if (match != null) {
          await _budgets.updateAmount(match.id, amount);
          return AssistantAnswer('Ya tenías un límite en ${intent.categoryName} de ${_money(match.amountMinor)} — lo actualicé a ${_money(amount)}.');
        }
        await _budgets.createCategoryBudget(categoryId: intent.categoryId!, amountMinor: amount);
        return AssistantAnswer('Listo: te aviso si gastas más de ${_money(amount)} en ${intent.categoryName} este mes.');
      case AlertGoal.overallLimit:
        final match = existing.where((b) => b.kind == BudgetKind.overallExpense).firstOrNull;
        if (match != null) {
          await _budgets.updateAmount(match.id, amount);
          return AssistantAnswer('Ya tenías un límite general de ${_money(match.amountMinor)} — lo actualicé a ${_money(amount)}.');
        }
        await _budgets.createOverallExpenseBudget(amountMinor: amount);
        return AssistantAnswer('Listo: te aviso si tus gastos totales superan ${_money(amount)} este mes.');
      case AlertGoal.savingsGoal:
        final match = existing.where((b) => b.kind == BudgetKind.savings).firstOrNull;
        if (match != null) {
          await _budgets.updateAmount(match.id, amount);
          return AssistantAnswer('Ya tenías una meta de ahorro de ${_money(match.amountMinor)} — la actualicé a ${_money(amount)}.');
        }
        await _budgets.createSavingsBudget(amountMinor: amount);
        return AssistantAnswer('Listo: te aviso cuando ahorres ${_money(amount)} este mes.');
    }
  }

  static const _helpText = 'Puedo ayudarte con cosas como:\n'
      '• "¿cuánto gasté hoy/esta semana/este mes?"\n'
      '• "¿cuánto gasté en Comida el mes pasado?"\n'
      '• "¿gasté más este mes que el pasado?"\n'
      '• "¿en qué categoría gasté más?"\n'
      '• "¿cómo van mis presupuestos?"\n'
      '• "mi saldo por cuenta"\n'
      '• "busca uber" (movimientos por nota)\n'
      '• "gasté 500 en comida" o "cobré 3000 de salario" (lo registro por ti; "deshacer" lo quita)\n'
      '• "avísame si gasto más de 5000 en Comida"\n'
      'Pregúntame como quieras, no hace falta que sea exacto.';

  static const _unknownText = 'No estoy seguro de haber entendido. Prueba con algo como "¿cuánto gasté este mes?" '
      'o escribe "ayuda" para ver más ejemplos.';
}
