import 'package:arnic_finance/core/theme.dart';
import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_account_repository.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/data/server_sync_prefs.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/platform/notifications.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:arnic_finance/domain/repositories.dart';
import 'package:arnic_finance/state/providers.dart';
import 'package:arnic_finance/ui/screens/add_movement_screen.dart';
import 'package:arnic_finance/ui/screens/assistant_screen.dart';
import 'package:arnic_finance/ui/screens/budgets_screen.dart';
import 'package:arnic_finance/ui/screens/cards_screen.dart';
import 'package:arnic_finance/ui/screens/history_screen.dart';
import 'package:arnic_finance/ui/screens/home_screen.dart';
import 'package:arnic_finance/ui/screens/review_screen.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Las notificaciones usan un plugin nativo que en pruebas no existe.
class _SilentNotifier extends BudgetNotifier {
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> init() async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('es'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> finish(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    });
  }

  Future<void> pumpScreen(WidgetTester tester, AppDatabase db, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverSyncPrefsProvider.overrideWithValue(ServerSyncPrefs(prefs, MemorySecretStore())),
        budgetNotifierProvider.overrideWithValue(_SilentNotifier()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: screen),
    ));
    await settle(tester);
  }

  /// Tarjeta de crédito con un consumo del banco sin clasificar y otro ya clasificado.
  Future<void> seedCard(AppDatabase db) async {
    await DriftAccountRepository(db).create(name: 'Tarjeta BHD', icon: '💳', kind: AccountKind.creditCard);
    final card = await (db.select(db.accounts)..where((a) => a.name.equals('Tarjeta BHD'))).getSingle();
    final repo = DriftMovementRepository(db);
    final now = DateTime.now();
    await repo.add(MovementInput(
      type: TxType.expense, amountMinor: 144537, categoryId: 'exp_other', accountId: card.id, occurredAt: now, note: 'AMAZON 1 (tarjeta ••8866)'));
    await repo.add(MovementInput(
      type: TxType.expense, amountMinor: 200000, categoryId: 'exp_fuel', accountId: card.id, occurredAt: now.subtract(const Duration(minutes: 5)), note: 'ECO PETROLEO (tarjeta ••8866)'));
  }

  testWidgets('Inicio: tarjeta con consumo, aviso "por revisar" y nota de tarjeta en el balance', (tester) async {
    final db = AppDatabase.inMemory();
    await tester.runAsync(() => seedCard(db));
    await pumpScreen(tester, db, const Scaffold(body: HomeScreen()));

    expect(find.text('Tarjetas'), findsOneWidget);
    expect(find.text('Tarjeta BHD'), findsOneWidget);
    expect(find.text('1 gasto del banco por revisar'), findsOneWidget);
    expect(find.textContaining('consumidos con tarjeta de crédito'), findsOneWidget);
    expect(find.textContaining('Promedio de'), findsOneWidget, reason: 'ritmo del mes');
    await finish(tester, db);
  });

  testWidgets('Por revisar: "Está bien" saca el gasto de la bandeja', (tester) async {
    final db = AppDatabase.inMemory();
    await tester.runAsync(() => seedCard(db));
    await pumpScreen(tester, db, const ReviewScreen());

    expect(find.textContaining('AMAZON 1'), findsOneWidget);
    expect(find.textContaining('ECO PETROLEO'), findsNothing, reason: 'ya tiene categoría');
    await tester.tap(find.text('Está bien'));
    await settle(tester);
    expect(find.textContaining('AMAZON 1'), findsNothing);
    expect(find.textContaining('Todo clasificado'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('Por revisar: elegir categoría reclasifica el gasto y lo saca de la bandeja', (tester) async {
    final db = AppDatabase.inMemory();
    await tester.runAsync(() => seedCard(db));
    await pumpScreen(tester, db, const ReviewScreen());

    await tester.tap(find.text('Elegir categoría'));
    await settle(tester);
    await tester.tap(find.textContaining('Compras'));
    await settle(tester);
    expect(find.textContaining('Todo clasificado'), findsOneWidget);
    final saved = await tester.runAsync(() => DriftMovementRepository(db).watch(const MovementFilter()).first);
    expect(saved!.where((m) => m.note!.startsWith('AMAZON')).single.category.id, 'exp_shopping');
    await finish(tester, db);
  });

  testWidgets('Tarjetas: "Agregar tarjeta" crea la cuenta sin salir a Ajustes', (tester) async {
    final db = AppDatabase.inMemory();
    await pumpScreen(tester, db, const CardsScreen());

    await tester.tap(find.text('Agregar tarjeta'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Tarjeta Banreservas');
    await tester.tap(find.text('Crear'));
    await settle(tester);
    expect(find.text('Tarjeta Banreservas'), findsOneWidget);
    expect(find.textContaining('Aún no tienes tarjetas'), findsNothing);
    await finish(tester, db);
  });

  testWidgets('Movimientos: la búsqueda filtra por comercio y ajusta los totales', (tester) async {
    final db = AppDatabase.inMemory();
    await tester.runAsync(() => seedCard(db));
    await pumpScreen(tester, db, const Scaffold(body: HistoryScreen()));

    expect(find.text('Combustible'), findsOneWidget);
    await tester.tap(find.byTooltip('Buscar'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'amazon');
    await settle(tester);
    expect(find.text('Combustible'), findsNothing);
    expect(find.text('Otros'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.textContaining('Nada coincide'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('Registrar: "Repetir" vuelve a llenar monto y categoría del último gasto', (tester) async {
    final db = AppDatabase.inMemory();
    await tester.runAsync(() => seedCard(db));
    await pumpScreen(tester, db, const AddMovementScreen());

    final repeat = find.textContaining('Repetir:');
    expect(repeat, findsOneWidget);
    await tester.tap(repeat);
    await settle(tester);
    expect(find.text('1,445.37'), findsOneWidget);
    expect(find.textContaining('Repetir:'), findsNothing, reason: 'ya hay monto');
    await finish(tester, db);
  });

  testWidgets('Asistente: "gasté 500 en gasolina" registra en Combustible y "deshacer" lo quita', (tester) async {
    final db = AppDatabase.inMemory();
    await pumpScreen(tester, db, const AssistantScreen());

    Future<void> say(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.byIcon(Icons.send));
      await settle(tester);
    }

    Future<List<Movement>> saved() async => (await tester.runAsync(() => DriftMovementRepository(db).watch(const MovementFilter()).first))!;

    await say('gasté 500 en gasolina');
    expect(find.textContaining('Listo: Gasto de RD\$500 en Combustible'), findsOneWidget);
    var list = await saved();
    expect((list.single.amountMinor, list.single.category.id, list.single.note), (50000, 'exp_fuel', 'gasolina'));

    await say('deshacer');
    expect(find.text('Listo, lo quité.'), findsOneWidget);
    list = await saved();
    expect(list, isEmpty);

    await say('deshacer');
    expect(find.textContaining('nada reciente'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('Presupuestos: sugiere límites según meses anteriores y un toque crea el presupuesto', (tester) async {
    final db = AppDatabase.inMemory();
    await tester.runAsync(() async {
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 10);
      final repo = DriftMovementRepository(db);
      await repo.add(MovementInput(type: TxType.expense, amountMinor: 650000, categoryId: 'exp_food', accountId: 'acc_cash', occurredAt: lastMonth));
    });
    await pumpScreen(tester, db, const BudgetsScreen());

    expect(find.text('Sugeridos para ti'), findsOneWidget);
    expect(find.textContaining('Gastas ~RD\$6,500 al mes'), findsOneWidget);
    // El nombre debe tener ancho real (un botón de ancho infinito lo dejaba de una letra por línea).
    expect(tester.getSize(find.text('Comida')).width, greaterThan(50));
    await tester.tap(find.widgetWithText(FilledButton, 'RD\$6,500'));
    await settle(tester);
    expect(find.text('Sugeridos para ti'), findsNothing, reason: 'ya tiene presupuesto en esa categoría');
    expect(find.textContaining('Comida'), findsWidgets);
    await finish(tester, db);
  });
}
