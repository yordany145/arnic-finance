import 'budget.dart';
import 'date_range.dart';
import 'enums.dart';
import 'models.dart';

/// Contratos de acceso a datos. La UI y el estado sólo conocen estas interfaces:
/// para añadir sincronización en la nube bastará con otra implementación (o un
/// decorador sobre la local) sin tocar pantallas.

class MovementFilter {
  const MovementFilter({this.type, this.categoryId, this.accountId, this.range, this.limit, this.noteQuery});

  final TxType? type;
  final String? categoryId;
  final String? accountId;

  /// `null` = todo el historial.
  final DateRange? range;
  final int? limit;

  /// Sólo movimientos cuya nota contenga este texto (sin distinguir
  /// mayúsculas/minúsculas). Usado por el asistente para buscar por palabra.
  final String? noteQuery;

  @override
  bool operator ==(Object other) =>
      other is MovementFilter &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.accountId == accountId &&
      other.range == range &&
      other.limit == limit &&
      other.noteQuery == noteQuery;

  @override
  int get hashCode => Object.hash(type, categoryId, accountId, range, limit, noteQuery);
}

abstract interface class MovementRepository {
  Stream<List<Movement>> watch(MovementFilter filter);

  /// Ingresos/gastos del filtro; ignora [MovementFilter.type] y [MovementFilter.limit].
  Stream<PeriodSummary> watchSummary(MovementFilter filter);

  Future<Movement?> getById(String id);
  Future<String> add(MovementInput input);
  Future<void> update(String id, MovementInput input);
  Future<void> delete(String id);
  Future<void> restore(String id);
}

abstract interface class CategoryRepository {
  Stream<List<Category>> watch(TxType type);

  /// Igual que [watch] pero las más usadas primero (para el formulario rápido).
  Stream<List<Category>> watchByUsage(TxType type);
  Future<Category?> getById(String id);
  Future<void> create({required String name, required String icon, required TxType type});
  Future<void> update(String id, {required String name, required String icon});
  Future<void> delete(String id);
}

abstract interface class AccountRepository {
  Stream<List<Account>> watch();
  Future<void> create({required String name, required String icon, required AccountKind kind});
  Future<void> update(String id, {required String name, required String icon, required AccountKind kind});
  Future<void> delete(String id);
}

abstract interface class SettingsRepository {
  Stream<String> watchCurrencySymbol();
  Future<void> setCurrencySymbol(String symbol);
  Stream<String?> watchDefaultAccountId();
  Future<void> setDefaultAccountId(String id);
}

abstract interface class BudgetRepository {
  Stream<List<Budget>> watch();

  /// Progreso de cada presupuesto activo en el mes indicado por [now].
  Stream<List<BudgetProgress>> watchProgress(DateTime now);

  Future<void> createCategoryBudget({required String categoryId, required int amountMinor});
  Future<void> createOverallExpenseBudget({required int amountMinor});
  Future<void> createSavingsBudget({required int amountMinor});
  Future<void> updateAmount(String id, int amountMinor);
  Future<void> delete(String id);

  /// `true` si es la primera vez que se cruza este nivel en este período
  /// (y deja constancia, para no repetir el aviso). Se usa justo antes de notificar.
  Future<bool> markAlertIfNew(String budgetId, String periodKey, AlertLevel level);
}
