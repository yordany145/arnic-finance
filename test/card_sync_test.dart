import 'dart:convert';

import 'package:arnic_finance/data/card_settings_store.dart';
import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/data/server_sync_client.dart';
import 'package:arnic_finance/data/server_sync_prefs.dart';
import 'package:arnic_finance/data/server_sync_service.dart';
import 'package:arnic_finance/domain/card_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late CardSettingsStore store;
  late ServerSyncPrefs prefs;
  late List<String> calls;
  late int configChanged;

  setUp(() async {
    db = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final raw = await SharedPreferences.getInstance();
    store = CardSettingsStore(raw);
    prefs = ServerSyncPrefs(raw, MemorySecretStore());
    await prefs.setCredentials(serverUrl: 'https://servidor.ejemplo', apiKey: 'k');
    calls = [];
    configChanged = 0;
  });
  tearDown(() => db.close());

  /// `remote`: null = el servidor no tiene /v1/config (404); si no, {updatedAt, config}.
  ServerSyncService service({Map<String, dynamic>? remote, int configStatus = 200}) {
    final client = ServerSyncClient(
      httpClient: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        Map<String, dynamic> json(Object o) => o as Map<String, dynamic>;
        if (req.url.path == '/v1/sync') {
          return http.Response(jsonEncode({'serverTimeMs': 1, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []}), 200);
        }
        if (req.url.path == '/v1/config' && req.method == 'GET') {
          if (configStatus != 200) return http.Response(jsonEncode({'error': 'x'}), configStatus);
          return remote == null ? http.Response('{}', 404) : http.Response(jsonEncode(remote), 200);
        }
        if (req.url.path == '/v1/config' && req.method == 'PUT') {
          calls.add('PUT-body ${jsonEncode(json(jsonDecode(req.body)))}');
          return http.Response(jsonEncode({'updatedAt': 1}), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    return ServerSyncService(db, client, prefs, cardStore: store, onConfigChanged: () => configChanged++);
  }

  test('el servidor tiene algo más nuevo: se guarda localmente y se avisa a la UI', () async {
    await store.write(const CardSettings().withCard(const CardConfig(accountId: 'a', limitMinor: 100), 1000));
    await service(remote: {
      'updatedAt': 2000,
      'config': {'cards': [{'accountId': 'a', 'limitMinor': 1500000, 'cutDay': 15, 'dueDay': 5}]},
    }).syncNow();

    final local = store.read();
    expect(local.updatedAt, 2000);
    expect(local.forAccount('a')?.limitMinor, 1500000);
    expect(local.forAccount('a')?.cutDay, 15);
    expect(configChanged, 1);
    expect(calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  test('lo local es más nuevo (el usuario editó en la app): se envía al servidor', () async {
    await store.write(const CardSettings().withCard(const CardConfig(accountId: 'a', limitMinor: 3000000, cutDay: 20, dueDay: 8), 5000));
    await service(remote: {'updatedAt': 1000, 'config': <String, dynamic>{}}).syncNow();

    final put = calls.firstWhere((c) => c.startsWith('PUT-body'));
    expect(put, contains('"updatedAt":5000'));
    expect(put, contains('"limitMinor":3000000'));
    expect(put, contains('"cutDay":20'));
    expect(configChanged, 0);
  });

  test('misma hora: no hace nada', () async {
    await store.write(const CardSettings().withCard(const CardConfig(accountId: 'a'), 3000));
    await service(remote: {'updatedAt': 3000, 'config': <String, dynamic>{}}).syncNow();
    expect(calls.where((c) => c.contains('/v1/config') && c.startsWith('PUT')), isEmpty);
    expect(configChanged, 0);
  });

  test('un servidor sin /v1/config (versión anterior) no rompe la sincronización', () async {
    await store.write(const CardSettings().withCard(const CardConfig(accountId: 'a'), 3000));
    await service(remote: null).syncNow();
    expect(store.read().updatedAt, 3000);
  });

  test('un error del servidor al leer la configuración no hace fallar la sincronización de movimientos', () async {
    await service(configStatus: 500).syncNow(); // no lanza
    expect(calls, contains('GET /v1/sync'));
  });
}
