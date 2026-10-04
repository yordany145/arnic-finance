import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_account_repository.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/data/server_sync_prefs.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:arnic_finance/state/providers.dart';
import 'package:arnic_finance/ui/screens/cards_screen.dart';
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

  Future<void> finish(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    });
  }

  testWidgets('Tarjetas: sin tarjetas muestra la ayuda', (tester) async {
    final db = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverSyncPrefsProvider.overrideWithValue(ServerSyncPrefs(prefs, MemorySecretStore())),
      ],
      child: const MaterialApp(home: CardsScreen()),
    ));
    await settle(tester);
    expect(find.textContaining('Aún no tienes tarjetas'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('Tarjetas: configurar límite y día de corte; muestra % usado, disponible y el ciclo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final db = AppDatabase.inMemory();
    await tester.runAsync(() async {
      await DriftAccountRepository(db).create(name: 'Tarjeta BHD', icon: '💳', kind: AccountKind.creditCard);
      final account = await (db.select(db.accounts)..where((a) => a.name.equals('Tarjeta BHD'))).getSingle();
      await DriftMovementRepository(db).add(MovementInput(
        type: TxType.expense,
        amountMinor: 500000, // RD$5,000
        categoryId: 'exp_food',
        accountId: account.id,
        occurredAt: DateTime(2026, 10, 3),
      ));
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
      child: const MaterialApp(home: CardsScreen()),
    ));
    await settle(tester);

    // Sin configurar: muestra lo consumido y pide el límite.
    expect(find.text('Tarjeta BHD'), findsOneWidget);
    expect(find.textContaining('Toca para poner el límite'), findsOneWidget);
    expect(find.text('Sin fecha de pago'), findsOneWidget);

    await tester.tap(find.text('Tarjeta BHD'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '30000');
    await tester.tap(find.byType(DropdownButtonFormField<int?>).first); // día de corte
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día 15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int?>).last); // día de pago
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día 5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await settle(tester);

    expect(find.textContaining('(17%)'), findsOneWidget); // 5,000 de 30,000
    expect(find.textContaining('Disponible RD\$25,000'), findsOneWidget);
    expect(find.textContaining('Ciclo 16/09–15/10'), findsOneWidget);
    expect(find.textContaining('Pago 5 nov'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(CardsScreen)));
    final saved = container.read(cardSettingsProvider).cards.values.single;
    expect((saved.limitMinor, saved.cutDay, saved.dueDay), (3000000, 15, 5));
    expect(prefs.getString('card_settings_v1'), contains('3000000')); // quedó guardado en el teléfono
    await finish(tester, db);
  });
}
