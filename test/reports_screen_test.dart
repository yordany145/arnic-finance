import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/data/server_sync_prefs.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:arnic_finance/state/providers.dart';
import 'package:arnic_finance/ui/screens/reports_screen.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('es'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('Reportes: gasto por categoría del mes, navegar al mes anterior y estado vacío', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final db = AppDatabase.inMemory();
    await tester.runAsync(() async {
      final repo = DriftMovementRepository(db);
      Future<void> add(String cat, int minor, DateTime at) => repo.add(MovementInput(type: TxType.expense, amountMinor: minor, categoryId: cat, accountId: kDefaultAccountId, occurredAt: at));
      await add('exp_fuel', 490000, DateTime(2026, 10, 2));
      await add('exp_food', 150000, DateTime(2026, 10, 5));
      await add('exp_food', 99900, DateTime(2026, 9, 20));
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverSyncPrefsProvider.overrideWithValue(ServerSyncPrefs(prefs, MemorySecretStore())),
        nowProvider.overrideWithValue(DateTime(2026, 10, 15, 12)),
      ],
      child: const MaterialApp(home: ReportsScreen()),
    ));
    await settle(tester);

    expect(find.text('Octubre de 2026'), findsOneWidget);
    expect(find.text('Combustible'), findsOneWidget);
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text('RD\$6,400'), findsWidgets); // gastos del mes: 4,900 + 1,500
    expect(find.text('77%'), findsOneWidget); // combustible: 4,900 de 6,400

    await tester.tap(find.byTooltip('Mes anterior'));
    await settle(tester);
    expect(find.text('Septiembre de 2026'), findsOneWidget);
    expect(find.text('Combustible'), findsNothing);
    expect(find.text('100%'), findsOneWidget); // septiembre: solo comida

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Mes anterior'));
      await settle(tester);
    }
    expect(find.text('Mayo de 2026'), findsOneWidget);
    expect(find.textContaining('No hay gastos registrados'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed, isNull); // tope de 6 meses

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    });
  });
}
