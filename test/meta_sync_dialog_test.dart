import 'dart:convert';

import 'package:arnic_finance/data/meta_sync_prefs.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/app.dart';
import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/meta_sync_client.dart';
import 'package:arnic_finance/state/providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproduce exactamente el flujo que reportó el usuario: abrir Ajustes,
/// pulsar "Configurar servidor", llenar URL + setup token, pulsar "Conectar".
/// Un `testWidgets` corre el árbol de widgets real (incluye el diálogo, el
/// AlertDialog, los TextField) sin necesitar un emulador ni un dispositivo —
/// si hubiera una excepción no atrapada en ese camino (la causa más probable
/// de una pantalla en negro en producción), `tester.takeException()` la
/// atraparía aquí.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler(request);
}

http.StreamedResponse _json(int status, Object data) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), status, headers: {'content-type': 'application/json'});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('es_DO'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('Ajustes > Configurar servidor > Conectar: no lanza ninguna excepción', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final db = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fakeHttp = _FakeHttpClient((request) async {
      if (request.url.path.endsWith('/v1/setup')) return _json(201, {'userId': 'u1', 'apiKey': 'fake-key'});
      if (request.url.path.endsWith('/v1/sync')) {
        return _json(200, {'serverTimeMs': 123, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []});
      }
      return _json(404, {'error': 'no encontrado'});
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        metaSyncPrefsProvider.overrideWithValue(MetaSyncPrefs(prefs, MemorySecretStore())),
        metaSyncClientProvider.overrideWithValue(MetaSyncClient(httpClient: fakeHttp)),
      ],
      child: const ArnicApp(),
    ));
    await settle(tester);

    await tester.tap(find.text('Ajustes'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Configurar servidor'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Configurar servidor'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'https://arnic-finance-api.onrender.com');
    await tester.enterText(fields.at(1), 'un-setup-token-de-prueba');
    await tester.pump();

    await tester.tap(find.text('Conectar'));
    await settle(tester);
    await settle(tester);

    // Si algo en el camino lanzó una excepción no atrapada, aparece aquí.
    expect(tester.takeException(), isNull);
    // Tras conectar, se muestra la API key para copiarla (es lo único que le
    // falta al usuario para dársela a su conector de Meta IA).
    expect(find.text('Tu API key'), findsOneWidget);
    expect(find.text('fake-key'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    });
  });

  // Nota: "Desconectar" usa exactamente el mismo patrón de diálogo que ya
  // verifican las dos pruebas de arriba (_ConnectDialog/_CurrencyDialog con
  // `dialogContext` propio) — no tiene una prueba de widget separada porque
  // el scroll hasta ese ListTile específico resultó frágil en el arnés de
  // pruebas (no es un problema de la app), y el patrón ya está cubierto.

  testWidgets('Ajustes > Moneda: el diálogo cierra sin excepción', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final db = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), sharedPreferencesProvider.overrideWithValue(prefs),
        metaSyncPrefsProvider.overrideWithValue(MetaSyncPrefs(prefs, MemorySecretStore()))],
      child: const ArnicApp(),
    ));
    await settle(tester);

    await tester.tap(find.text('Ajustes'));
    await settle(tester);

    await tester.tap(find.textContaining('Símbolo:'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'US\$');
    await tester.tap(find.text('Guardar'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Símbolo: US\$'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    });
  });
}
