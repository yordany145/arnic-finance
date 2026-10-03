import 'movement_input_helper.dart';
import 'package:arnic_finance/data/meta_sync_prefs.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/app.dart';
import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/state/providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() => initializeDateFormatting('es_DO'));

  /// drift consulta en un isolate real: hay que ceder tiempo real (runAsync) y
  /// después avanzar el reloj falso; `pumpAndSettle` solo no vería los datos.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Desmonta el árbol y deja correr los timers de cancelación de streams de drift
  /// ANTES de terminar el test (Flutter exige que no queden timers pendientes).
  Future<void> finish(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    });
  }

  Future<AppDatabase> pumpApp(WidgetTester tester, {Future<void> Function(AppDatabase db)? seed}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase.inMemory();
    // Datos iniciales ANTES de montar la app (aún sin streams escuchando).
    if (seed != null) await tester.runAsync(() => seed(db));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        metaSyncPrefsProvider.overrideWithValue(MetaSyncPrefs(prefs, MemorySecretStore())),
      ],
      child: const ArnicApp(),
    ));
    await settle(tester);
    return db;
  }

  Future<void> tapKeys(WidgetTester tester, String keys) async {
    for (final k in keys.split('')) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
  }

  testWidgets('Registrar un gasto de 350: monto → Guardar (categoría por defecto Comida)', (tester) async {
    final db = await pumpApp(tester);
    expect(find.text('Balance actual'), findsOneWidget);
    expect(find.textContaining('Aún no hay movimientos'), findsOneWidget);

    await tester.tap(find.text('Registrar'));
    await settle(tester);
    await tapKeys(tester, '350');
    expect(find.text('350'), findsWidgets);
    await tester.tap(find.text('GUARDAR'));
    await settle(tester);

    final saved = (await tester.runAsync(() => db.select(db.transactions).get()))!;
    expect(saved, hasLength(1));
    expect(saved.single.amountMinor, 35000);
    expect(saved.single.categoryId, 'exp_food');
    expect(saved.single.type.name, 'expense');

    // Vuelve a Inicio, con el movimiento en "Recientes" y el balance negativo.
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text('-RD\$350'), findsWidgets);
    expect(find.textContaining('Gasto guardado'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('Ingreso con otra categoría y nota', (tester) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);
    await tester.tap(find.text('INGRESO'));
    await settle(tester);
    await tapKeys(tester, '25000');
    await tester.tap(find.textContaining('Negocio'));
    await tester.pump();
    // El campo de nota queda bajo los chips: hay que desplazar la lista hasta él.
    await tester.scrollUntilVisible(find.byType(TextField), 120, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), 'venta del sábado');
    await tester.pump();
    // El teclado del sistema (simulado) oculta el keypad, pero GUARDAR sigue visible.
    await tester.tap(find.text('GUARDAR'));
    await settle(tester);

    final m = await tester.runAsync(() async {
      final rows = await db.select(db.transactions).get();
      return rows.single;
    });
    expect(m!.amountMinor, 2500000);
    expect(m.categoryId, 'inc_business');
    expect(m.note, 'venta del sábado');
    expect(m.type.name, 'income');
    await finish(tester, db);
  });

  testWidgets('Guardar sin monto no crea nada', (tester) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);
    await tester.tap(find.text('GUARDAR'));
    await tester.pump();
    expect(find.text('Escribe un monto'), findsOneWidget);
    final rows = (await tester.runAsync(() => db.select(db.transactions).get()))!;
    expect(rows, isEmpty);
    await finish(tester, db);
  });

  testWidgets('Historial: filtra por tipo y muestra totales', (tester) async {
    final now = DateTime.now();
    final db = await pumpApp(tester, seed: (db) async {
      final repo = DriftMovementRepository(db);
      await repo.add(MovementInputHelper.make('expense', 50000, 'exp_food', now));
      await repo.add(MovementInputHelper.make('expense', 150000, 'exp_fuel', now));
      await repo.add(MovementInputHelper.make('income', 2500000, 'inc_salary', now));
    });

    await tester.tap(find.text('Movimientos'));
    await settle(tester);
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('+RD\$25,000'), findsOneWidget);
    expect(find.text('-RD\$1,500'), findsOneWidget);

    await tester.tap(find.text('Gastos').first);
    await settle(tester);
    expect(find.text('+RD\$25,000'), findsNothing);
    expect(find.text('-RD\$1,500'), findsOneWidget);
    await finish(tester, db);
  });
}
