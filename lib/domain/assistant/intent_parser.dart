import '../enums.dart';
import '../models.dart';
import 'amount_parser.dart';
import 'assistant_intent.dart';
import 'period_parser.dart';
import 'text_normalize.dart';

/// Interpreta un mensaje en español libre y lo convierte en un [AssistantIntent].
///
/// No es NLU de verdad: es una cascada de reglas ordenadas de más a menos
/// específica (una alerta ("avísame si...") se reconoce ANTES que una
/// pregunta de totales, porque ambas mencionan "gasto"). El orden de los
/// `if` en [parse] importa tanto como las propias reglas — no reordenar sin
/// releer los comentarios de cada bloque.
class IntentParser {
  const IntentParser();

  AssistantIntent parse(
    String rawText, {
    required List<Category> expenseCategories,
    required List<Category> incomeCategories,
    required List<Account> accounts,
    required DateTime now,
  }) {
    final text = normalize(rawText);
    if (text.isEmpty) return const UnknownIntent();

    if (RegExp(r'^(hola|buenas|buenos dias|buenas tardes|buenas noches|hey|que tal)[!. ]*$').hasMatch(text)) {
      return const GreetingIntent();
    }
    if (RegExp(r'^(gracias|muchas gracias|genial|perfecto|excelente|ok|vale)[!. ]*$').hasMatch(text)) {
      return const ThanksIntent();
    }
    if (text.contains('ayuda') || text.contains('que puedes hacer') || text.contains('que sabes hacer') || text == 'help') {
      return const HelpIntent();
    }

    final allCategories = [...expenseCategories, ...incomeCategories];
    final category = _findCategory(text, allCategories);
    final account = _findAccount(text, accounts);

    // Se quita del texto lo que ya se identificó, para que el resto del
    // análisis (monto, tipo) no lo confunda con otra cosa. Se vuelven a
    // colapsar los espacios después: un hueco de varias palabras tapadas no
    // debe romper una frase de dos palabras que quedó a caballo (p. ej.
    // "más que" si justo antes se tapó "este mes").
    var working = text;
    final period = extractPeriod(working, now);
    if (period != null) working = maskSpan(working, period.start, period.end);
    if (category != null) working = working.replaceFirst(normalize(category.name), ' ');
    if (account != null) working = working.replaceFirst(normalize(account.name), ' ');
    working = working.replaceAll(RegExp(r'\s+'), ' ').trim();

    final isAlertRequest = RegExp(r'avisa|notifica|avisame|notificame').hasMatch(text);
    if (isAlertRequest) return _parseAlert(working, category: category);

    final register = _parseRegister(text, working, period, expenseCategories, incomeCategories, account);
    if (register != null) return register;

    if (RegExp(r'busca(?:r)?\s+(.+)').hasMatch(working)) {
      final q = RegExp(r'busca(?:r)?\s+(.+)').firstMatch(working)!.group(1)!.trim();
      if (q.isNotEmpty) return SearchMovementsIntent(query: q, period: period);
    }
    final movDe = RegExp(r'movimientos? (?:de|con|sobre) (.+)').firstMatch(working);
    if (movDe != null && movDe.group(1)!.trim().isNotEmpty) {
      return SearchMovementsIntent(query: movDe.group(1)!.trim(), period: period);
    }

    if (RegExp(r'ultim[oa]s? movimientos|movimientos recientes|recientes').hasMatch(working)) {
      return RecentMovementsIntent(type: _findType(working));
    }
    if (RegExp(r'ultimo gasto|mi ultimo gasto').hasMatch(working)) return const RecentMovementsIntent(type: TxType.expense);
    if (RegExp(r'ultimo ingreso|mi ultimo ingreso').hasMatch(working)) return const RecentMovementsIntent(type: TxType.income);

    final compareType = RegExp(r'compar|mas que|menos que').hasMatch(working) ? (_findType(working) ?? TxType.expense) : null;
    if (compareType != null) {
      // El período ("esta semana") ya se enmascaró de `working`: se usa el
      // período ya reconocido, o si no hubo, el texto original sin tapar.
      final wantsWeek = period?.label.contains('semana') ?? text.contains('semana');
      final currentLabel = wantsWeek ? 'esta semana' : 'este mes';
      final current = extractPeriod(currentLabel, now)!;
      final previous = extractPeriod(wantsWeek ? 'semana pasada' : 'mes pasado', now)!;
      return CompareIntent(type: compareType, currentLabel: currentLabel, current: current, previous: previous);
    }

    if (RegExp(r'\btop\b|mayor gasto|principales categorias|en que gaste mas|en que categoria gaste mas').hasMatch(working)) {
      return TopCategoriesIntent(type: working.contains('ingreso') ? TxType.income : TxType.expense, period: period);
    }

    if (RegExp(r'promedio').hasMatch(working)) {
      return AverageIntent(type: working.contains('ingreso') ? TxType.income : TxType.expense, period: period);
    }

    if (RegExp(r'presupuesto|limite|límite|meta de ahorro').hasMatch(working)) {
      return const BudgetsStatusIntent();
    }

    if (RegExp(r'\bcuentas\b|saldo por cuenta').hasMatch(working) || (account == null && working.contains('cuanto tengo en'))) {
      return const AccountsStatusIntent();
    }
    if (account != null && RegExp(r'cuanto tengo|saldo|balance').hasMatch(working)) {
      return const AccountsStatusIntent();
    }

    if (RegExp(r'\bbalance\b|cuanto tengo|cuanto dinero tengo|mi saldo').hasMatch(working) && category == null) {
      return const BalanceIntent();
    }

    final type = _findType(working);
    final mentionsMoney = type != null || category != null || period != null || working.contains('cuanto');
    if (mentionsMoney) {
      return TotalsIntent(
        type: type,
        period: period,
        categoryId: category?.id,
        categoryName: category?.name,
        accountId: account?.id,
        accountName: account?.name,
      );
    }

    return const UnknownIntent();
  }

  static final _expenseVerb = RegExp(r'\b(gaste|pague|compre|gastamos|pagamos|compramos)\b|\b(anota|anotame|registra|registrame|apunta|apuntame)\b.*\bgasto\b');
  static final _incomeVerb = RegExp(r'\b(ingrese|cobre|recibi|gane|vendi|me pagaron|me depositaron)\b|\b(anota|anotame|registra|registrame|apunta|apuntame)\b.*\bingreso\b');
  static final _questionWord = RegExp(r'\b(cuanto|cuantos|cuanta|cuantas|que|cual|cuales|donde|quien|como)\b');
  static final _noteNoise = RegExp(
      r'\b(gaste|pague|compre|gastamos|pagamos|compramos|ingrese|cobre|recibi|gane|vendi|me pagaron|me depositaron|anota|anotame|registra|registrame|apunta|apuntame|un|una|el|la|los|las|de|del|en|por|para|con|mi|me|gasto|ingreso|pesos|peso|rd)\b|[\$,]');

  /// Palabras que delatan la categoría aunque el usuario no la nombre ("gasolina" → Combustible).
  static const _categoryHints = <String, String>{
    'gasolina': 'combustible', 'gasoil': 'combustible', 'diesel': 'combustible',
    'almuerzo': 'comida', 'cena': 'comida', 'desayuno': 'comida', 'supermercado': 'comida', 'colmado': 'comida',
    'restaurante': 'comida', 'pizza': 'comida', 'super': 'comida',
    'uber': 'transporte', 'taxi': 'transporte', 'guagua': 'transporte', 'pasaje': 'transporte', 'peaje': 'transporte',
    'luz': 'servicios', 'agua': 'servicios', 'internet': 'servicios', 'telefono': 'servicios', 'cable': 'servicios',
    'farmacia': 'salud', 'medico': 'salud', 'doctor': 'salud', 'medicina': 'salud',
    'netflix': 'suscripciones', 'spotify': 'suscripciones', 'youtube': 'suscripciones',
    'cine': 'entretenimiento', 'fiesta': 'entretenimiento',
    'alquiler': 'hogar', 'renta': 'hogar',
    'sueldo': 'salario', 'nomina': 'salario', 'quincena': 'salario',
  };

  /// Un mensaje en primera persona y pasado ("gasté 500 en comida") es un registro, no una pregunta.
  RegisterMovementIntent? _parseRegister(
    String text,
    String working,
    PeriodExtraction? period,
    List<Category> expenseCategories,
    List<Category> incomeCategories,
    Account? account,
  ) {
    if (text.contains('?') || _questionWord.hasMatch(working)) return null;
    final expense = _expenseVerb.hasMatch(working);
    final income = _incomeVerb.hasMatch(working);
    if (expense == income) return null; // ninguno, o ambos: ambiguo
    final amount = extractAmountMinor(working);
    if (amount == null || amount <= 0) return null;
    final type = expense ? TxType.expense : TxType.income;
    final categories = expense ? expenseCategories : incomeCategories;
    if (categories.isEmpty) return null;

    var category = _findCategory(text, categories);
    if (category == null) {
      for (final word in working.split(' ')) {
        final hint = _categoryHints[word];
        if (hint == null) continue;
        category = categories.where((c) => normalize(c.name) == hint).firstOrNull;
        if (category != null) break;
      }
    }
    category ??= categories.where((c) => normalize(c.name) == 'otros').firstOrNull ?? categories.last;

    var note = working.replaceFirst(RegExp(r'\d[\d,]*(?:\.\d+)?\s*(?:mil|k)?\b'), ' ');
    note = note.replaceAll(_noteNoise, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return RegisterMovementIntent(
      type: type,
      amountMinor: amount,
      categoryId: category.id,
      categoryName: category.name,
      accountId: account?.id,
      note: note.isEmpty ? null : note,
      yesterday: period?.label == 'ayer',
    );
  }

  AssistantIntent _parseAlert(String working, {Category? category}) {
    final amount = extractAmountMinor(working);
    final wantsSavings = RegExp(r'ahorr').hasMatch(working);
    if (wantsSavings) {
      return CreateAlertIntent(goal: AlertGoal.savingsGoal, amountMinor: amount);
    }
    if (category != null) {
      return CreateAlertIntent(goal: AlertGoal.categoryLimit, amountMinor: amount, categoryId: category.id, categoryName: category.name);
    }
    final mentionsBalance = RegExp(r'balance|saldo').hasMatch(working);
    if (mentionsBalance) {
      return const UnsupportedAlertIntent(
        'Todavía no puedo avisarte por el balance total (sólo por límites de categoría, límite general de gastos o metas de ahorro).',
      );
    }
    return CreateAlertIntent(goal: AlertGoal.overallLimit, amountMinor: amount);
  }

  TxType? _findType(String text) {
    final expense = RegExp(r'gast[eoa]|gastado|pague|pagué|compre|compré|egreso').hasMatch(text);
    final income = RegExp(r'ingres[eoa]|gane|gané|entrada|cobre|cobré|recibi|recibí|vendi|vendí').hasMatch(text);
    if (expense && !income) return TxType.expense;
    if (income && !expense) return TxType.income;
    return null;
  }

  Category? _findCategory(String text, List<Category> categories) {
    Category? best;
    var bestLength = 0;
    for (final c in categories) {
      final name = normalize(c.name);
      if (name.length > bestLength && containsWord(text, name)) {
        best = c;
        bestLength = name.length;
      }
    }
    return best;
  }

  Account? _findAccount(String text, List<Account> accounts) {
    Account? best;
    var bestLength = 0;
    for (final a in accounts) {
      final name = normalize(a.name);
      if (name.length > bestLength && containsWord(text, name)) {
        best = a;
        bestLength = name.length;
      }
    }
    return best;
  }
}
