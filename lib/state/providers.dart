import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/money.dart';
import '../data/card_settings_store.dart';
import '../data/app_lock_prefs.dart';
import '../data/database.dart';
import '../data/server_sync_client.dart';
import '../data/server_sync_prefs.dart';
import '../data/server_sync_service.dart';
import '../data/repositories/drift_account_repository.dart';
import '../data/reviewed_store.dart';
import '../data/repositories/drift_budget_repository.dart';
import '../data/repositories/drift_category_repository.dart';
import '../data/repositories/drift_movement_repository.dart';
import '../data/repositories/drift_settings_repository.dart';
import '../data/update_service.dart';
import '../domain/bank_movement.dart';
import '../domain/budget_suggestions.dart';
import '../domain/card_config.dart';
import '../domain/month_pace.dart';
import '../domain/budget.dart';
import '../domain/budget_alert_service.dart';
import '../domain/date_range.dart';
import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../platform/app_lock.dart';
import '../platform/notifications.dart';
import '../platform/quick_actions.dart';

/// Se sobrescribe en `main()` con la base abierta.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider no inicializado'));

/// Se sobrescribe en `main()` con la instancia ya cargada.
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPreferencesProvider no inicializado'));

// ── Bloqueo de la app ────────────────────────────────────────────────────────
final appLockPrefsProvider = Provider<AppLockPrefs>((ref) => AppLockPrefs(ref.watch(sharedPreferencesProvider)));

final appLockProvider = Provider<AppLock>((ref) => AppLock());

/// Estado en memoria de si el bloqueo está activado, sembrado desde
/// `AppLockPrefs` al arrancar. Notifier propio (no un stream) porque sólo esta
/// misma app lo cambia (no el registro rápido nativo).
class AppLockEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(appLockPrefsProvider).enabled;

  void set(bool value) {
    state = value;
    ref.read(appLockPrefsProvider).setEnabled(value);
  }
}

final appLockEnabledProvider = NotifierProvider<AppLockEnabledNotifier, bool>(AppLockEnabledNotifier.new);

/// `false` si el teléfono no tiene ninguna forma de desbloqueo configurada:
/// en ese caso no tiene sentido ofrecer el interruptor en Ajustes.
final appLockSupportedProvider = FutureProvider<bool>((ref) => ref.watch(appLockProvider).isSupported());

// ── Integración opcional con el servidor (ver docs/API.md) ──────────────────────
/// Se crea y se carga (`load()`) en main.dart: leer del Keystore es asíncrono.
final serverSyncPrefsProvider =
    Provider<ServerSyncPrefs>((ref) => throw UnimplementedError('serverSyncPrefsProvider no inicializado'));

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.close);
  return service;
});

final serverSyncClientProvider = Provider<ServerSyncClient>((ref) {
  final client = ServerSyncClient();
  ref.onDispose(client.close);
  return client;
});

final serverSyncServiceProvider = Provider<ServerSyncService>(
  (ref) => ServerSyncService(
    ref.watch(databaseProvider),
    ref.watch(serverSyncClientProvider),
    ref.watch(serverSyncPrefsProvider),
    cardStore: ref.watch(cardSettingsStoreProvider),
    onConfigChanged: () => ref.read(cardSettingsProvider.notifier).reload(),
  ),
);

// ── Tarjetas de crédito ──────────────────────────────────────────────────────
final cardSettingsStoreProvider = Provider<CardSettingsStore>((ref) => CardSettingsStore(ref.watch(sharedPreferencesProvider)));

class CardSettingsNotifier extends Notifier<CardSettings> {
  @override
  CardSettings build() => ref.watch(cardSettingsStoreProvider).read();

  /// Guarda la edición de una tarjeta (queda con la hora actual: gana al sincronizar).
  Future<void> save(CardConfig card) async {
    final next = state.withCard(card, DateTime.now().millisecondsSinceEpoch);
    state = next;
    await ref.read(cardSettingsStoreProvider).write(next);
  }

  /// Relee lo guardado (p. ej. tras bajar un cambio del servidor).
  void reload() => state = ref.read(cardSettingsStoreProvider).read();
}

final cardSettingsProvider = NotifierProvider<CardSettingsNotifier, CardSettings>(CardSettingsNotifier.new);

/// Consumo de una tarjeta en su ciclo actual. No descuenta pagos: mide lo consumido en el ciclo frente al límite.
class CardUsage {
  const CardUsage({required this.spentMinor, required this.range, this.limitMinor, this.due});

  final int spentMinor;
  final int? limitMinor;
  final DateRange range;
  final DateTime? due;

  double? get ratio => limitMinor == null || limitMinor == 0 ? null : spentMinor / limitMinor!;
  int? get availableMinor => limitMinor == null ? null : (limitMinor! - spentMinor).clamp(0, limitMinor!).toInt();
}

final cardUsageProvider = StreamProvider.family<CardUsage, String>((ref, accountId) {
  final config = ref.watch(cardSettingsProvider).forAccount(accountId);
  final now = ref.watch(nowProvider);
  final range = cardCycleRange(now, config?.cutDay);
  return ref
      .watch(movementRepositoryProvider)
      .watchSummary(MovementFilter(accountId: accountId, range: range))
      .map((s) => CardUsage(spentMinor: s.expenseMinor, limitMinor: config?.limitMinor, range: range, due: nextDueDate(now, config?.dueDay)));
});

/// Igual que `AppLockEnabledNotifier`: estado en memoria sembrado desde las
/// preferencias, para que la UI reaccione al toggle sin reconstruir la pantalla.
class ServerSyncEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(serverSyncPrefsProvider).enabled;

  void set(bool value) {
    state = value;
    ref.read(serverSyncPrefsProvider).setEnabled(value);
  }
}

final serverSyncEnabledProvider = NotifierProvider<ServerSyncEnabledNotifier, bool>(ServerSyncEnabledNotifier.new);

enum SyncState { idle, syncing, ok, error }

/// Resultado de la última sincronización con el servidor, para mostrarlo en Inicio:
/// sin esto un fallo (sin internet, clave inválida) pasa totalmente inadvertido.
class SyncStatus {
  const SyncStatus({this.state = SyncState.idle, this.lastOk});

  final SyncState state;
  final DateTime? lastOk;
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  void started() => state = SyncStatus(state: SyncState.syncing, lastOk: state.lastOk);
  void succeeded() => state = SyncStatus(state: SyncState.ok, lastOk: DateTime.now());
  void failed() => state = SyncStatus(state: SyncState.error, lastOk: state.lastOk);
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

/// Llamar tras guardar/editar/borrar/restaurar un movimiento (o presupuesto) y
/// al reanudar la app — igual que `checkBudgetAlerts`. No lanza si falla
/// (puede que no haya internet): una sincronización fallida nunca debe
/// impedir que el movimiento ya guardado se vea.
Future<void> syncWithServerIfEnabled(ProviderContainer container) async {
  final prefs = container.read(serverSyncPrefsProvider);
  if (!prefs.enabled || !prefs.isConfigured) return;
  final status = container.read(syncStatusProvider.notifier);
  status.started();
  try {
    await container.read(serverSyncServiceProvider).syncNow();
    status.succeeded();
  } catch (_) {
    // Ver comentario de arriba.
    status.failed();
  }
}

// ── Repositorios ─────────────────────────────────────────────────────────────
// Único punto donde se elige la implementación concreta (local). Una futura
// sincronización en la nube se enchufa aquí.
final movementRepositoryProvider =
    Provider<MovementRepository>((ref) => DriftMovementRepository(ref.watch(databaseProvider)));
final categoryRepositoryProvider =
    Provider<CategoryRepository>((ref) => DriftCategoryRepository(ref.watch(databaseProvider)));
final accountRepositoryProvider =
    Provider<AccountRepository>((ref) => DriftAccountRepository(ref.watch(databaseProvider)));
final budgetRepositoryProvider =
    Provider<BudgetRepository>((ref) => DriftBudgetRepository(ref.watch(databaseProvider)));
final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => DriftSettingsRepository(ref.watch(databaseProvider)));

final quickActionsProvider = Provider<QuickActions>((ref) => const QuickActions());

final budgetNotifierProvider = Provider<BudgetNotifier>((ref) => BudgetNotifier());

final budgetAlertServiceProvider = Provider<BudgetAlertService>((ref) {
  final notifier = ref.watch(budgetNotifierProvider);
  final currency = ref.watch(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
  return BudgetAlertService(
    ref.watch(budgetRepositoryProvider),
    (progress, level) => notifier.notify(progress, level, currency),
  );
});

/// Llamar después de cualquier cambio en movimientos (guardar/editar/borrar/
/// restaurar) y al reanudar la app. No lanza si falla (nunca debe romper el
/// guardado de un movimiento).
///
/// Recibe el [ProviderContainer] (no un [WidgetRef]) a propósito: se llama casi
/// siempre después de un `await` en un handler de UI, y un `WidgetRef` deja de
/// ser válido si el widget se desmontó mientras tanto. El container, en cambio,
/// vive mientras viva la app.
Future<void> checkBudgetAlerts(ProviderContainer container) async {
  try {
    await container.read(budgetAlertServiceProvider).check(container.read(nowProvider));
  } catch (_) {
    // Un aviso fallido no debe impedir que el movimiento ya guardado se vea.
  }
}

/// "Ahora". Se invalida al volver a primer plano para que "hoy" y "este mes"
/// no queden desfasados si la app estuvo abierta días.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());

// ── Datos de referencia ──────────────────────────────────────────────────────
final currencySymbolProvider =
    StreamProvider<String>((ref) => ref.watch(settingsRepositoryProvider).watchCurrencySymbol());

final categoriesProvider = StreamProvider.family<List<Category>, TxType>(
    (ref, type) => ref.watch(categoryRepositoryProvider).watch(type));

final categoriesByUsageProvider = StreamProvider.family<List<Category>, TxType>(
    (ref, type) => ref.watch(categoryRepositoryProvider).watchByUsage(type));

final accountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(accountRepositoryProvider).watch());

final defaultAccountIdProvider =
    StreamProvider<String?>((ref) => ref.watch(settingsRepositoryProvider).watchDefaultAccountId());

// ── Inicio ───────────────────────────────────────────────────────────────────
final creditCardAccountsProvider = Provider<List<Account>>((ref) {
  final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
  return [for (final a in accounts) if (a.kind == AccountKind.creditCard) a];
});

/// Ingresos/gastos acumulados de una cuenta (todo el historial).
final accountSummaryProvider = StreamProvider.family<PeriodSummary, String>(
    (ref, accountId) => ref.watch(movementRepositoryProvider).watchSummary(MovementFilter(accountId: accountId)));

/// Lo consumido en tarjetas de crédito (todo el historial, en positivo si se debe). Sirve para
/// explicar que parte del balance de Inicio es deuda de tarjeta y no dinero que ya salió.
final creditCardNetSpendProvider = Provider<int>((ref) {
  var total = 0;
  for (final card in ref.watch(creditCardAccountsProvider)) {
    total -= ref.watch(accountSummaryProvider(card.id)).value?.balanceMinor ?? 0;
  }
  return total;
});

final reviewedStoreProvider = Provider<ReviewedStore>((ref) => ReviewedStore(ref.watch(sharedPreferencesProvider)));

class ReviewedIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(reviewedStoreProvider).read();

  Future<void> markAll(Iterable<String> ids) async {
    state = {...state, ...ids};
    await ref.read(reviewedStoreProvider).write(state);
  }
}

final reviewedIdsProvider = NotifierProvider<ReviewedIdsNotifier, Set<String>>(ReviewedIdsNotifier.new);

/// Gastos que entraron solos del banco, quedaron en "Otros" y nadie ha confirmado (últimos 6 meses).
final reviewQueueProvider = Provider<List<Movement>>((ref) {
  final reviewed = ref.watch(reviewedIdsProvider);
  final movements = ref.watch(reportMovementsProvider).value ?? const <Movement>[];
  return [for (final m in movements) if (needsReview(m, reviewed)) m];
});

/// Ritmo de gasto del mes (promedio diario, proyección, y por día si hay límite general).
final monthPaceProvider = Provider<MonthPace?>((ref) {
  final month = ref.watch(monthSummaryProvider).value;
  if (month == null) return null;
  final budgets = ref.watch(budgetProgressProvider).value ?? const <BudgetProgress>[];
  final overall = budgets.where((p) => p.budget.kind == BudgetKind.overallExpense).firstOrNull;
  return computeMonthPace(spentMinor: month.expenseMinor, now: ref.watch(nowProvider), limitMinor: overall?.budget.amountMinor);
});

/// Límites sugeridos según el gasto de meses anteriores, sin repetir categorías con presupuesto.
final budgetSuggestionsProvider = Provider<List<BudgetSuggestion>>((ref) {
  final movements = ref.watch(reportMovementsProvider).value ?? const <Movement>[];
  final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
  return suggestBudgets(
    movements: movements,
    now: ref.watch(nowProvider),
    excludeCategoryIds: {for (final b in budgets) if (b.categoryId != null) b.categoryId!},
  );
});

/// Balance actual = todos los ingresos − todos los gastos.
final balanceSummaryProvider =
    StreamProvider<PeriodSummary>((ref) => ref.watch(movementRepositoryProvider).watchSummary(const MovementFilter()));

final monthSummaryProvider = StreamProvider<PeriodSummary>((ref) {
  final range = resolveRange(PeriodPreset.month, ref.watch(nowProvider));
  return ref.watch(movementRepositoryProvider).watchSummary(MovementFilter(range: range));
});

/// Movimientos de los últimos 6 meses (mes actual incluido), para la pantalla de reportes.
final reportMovementsProvider = StreamProvider<List<Movement>>((ref) {
  final now = ref.watch(nowProvider);
  final range = DateRange(DateTime(now.year, now.month - 5), DateTime(now.year, now.month + 1));
  return ref.watch(movementRepositoryProvider).watch(MovementFilter(range: range));
});

final recentMovementsProvider = StreamProvider<List<Movement>>(
    (ref) => ref.watch(movementRepositoryProvider).watch(const MovementFilter(limit: 6)));

// ── Presupuestos ─────────────────────────────────────────────────────────────
final budgetsProvider = StreamProvider<List<Budget>>((ref) => ref.watch(budgetRepositoryProvider).watch());

final budgetProgressProvider = StreamProvider<List<BudgetProgress>>(
    (ref) => ref.watch(budgetRepositoryProvider).watchProgress(ref.watch(nowProvider)));

// ── Historial ────────────────────────────────────────────────────────────────
class HistoryFilterState {
  const HistoryFilterState({
    this.type,
    this.categoryId,
    this.preset = PeriodPreset.month,
    this.customRange,
  });

  final TxType? type;
  final String? categoryId;
  final PeriodPreset preset;
  final DateRange? customRange;

  HistoryFilterState copyWith({
    TxType? type,
    bool clearType = false,
    String? categoryId,
    bool clearCategory = false,
    PeriodPreset? preset,
    DateRange? customRange,
  }) =>
      HistoryFilterState(
        type: clearType ? null : (type ?? this.type),
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        preset: preset ?? this.preset,
        customRange: customRange ?? this.customRange,
      );
}

class HistoryFilterNotifier extends Notifier<HistoryFilterState> {
  @override
  HistoryFilterState build() => const HistoryFilterState();

  /// Cambiar el tipo descarta la categoría si ya no corresponde.
  void setType(TxType? type, {Category? currentCategory}) {
    final keepCategory = type == null || currentCategory == null || currentCategory.type == type;
    state = state.copyWith(type: type, clearType: type == null, clearCategory: !keepCategory);
  }

  /// Elegir una categoría fija también el tipo, para no quedar en un filtro vacío.
  void setCategory(Category? category) {
    state = category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: category.id, type: category.type);
  }

  void setPreset(PeriodPreset preset) => state = state.copyWith(preset: preset);

  void setCustomRange(DateRange range) => state = state.copyWith(preset: PeriodPreset.custom, customRange: range);
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilterState>(HistoryFilterNotifier.new);

final historyRangeProvider = Provider<DateRange?>((ref) {
  final f = ref.watch(historyFilterProvider);
  return resolveRange(f.preset, ref.watch(nowProvider), custom: f.customRange);
});

final _historyFilterQueryProvider = Provider<MovementFilter>((ref) {
  final f = ref.watch(historyFilterProvider);
  return MovementFilter(type: f.type, categoryId: f.categoryId, range: ref.watch(historyRangeProvider));
});

final historyMovementsProvider = StreamProvider<List<Movement>>(
    (ref) => ref.watch(movementRepositoryProvider).watch(ref.watch(_historyFilterQueryProvider)));

/// Ingresos/gastos del período y la categoría elegidos (ignora el filtro de tipo,
/// para ver siempre ambos totales).
final historySummaryProvider = StreamProvider<PeriodSummary>(
    (ref) => ref.watch(movementRepositoryProvider).watchSummary(ref.watch(_historyFilterQueryProvider)));

/// Categoría actualmente filtrada (para mostrar su nombre en el chip).
final historyCategoryProvider = FutureProvider<Category?>((ref) async {
  final id = ref.watch(historyFilterProvider).categoryId;
  return id == null ? null : ref.watch(categoryRepositoryProvider).getById(id);
});
