import 'dart:convert';

import 'package:arnic_finance/data/database.dart';
import 'package:arnic_finance/data/server_sync_client.dart';
import 'package:arnic_finance/data/server_sync_prefs.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:arnic_finance/data/server_sync_service.dart';
import 'package:arnic_finance/data/repositories/drift_movement_repository.dart';
import 'package:arnic_finance/data/seed.dart';
import 'package:arnic_finance/domain/enums.dart';
import 'package:arnic_finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Doble de `http.Client`: nunca toca la red real, sólo simula las
/// respuestas del servidor descritas en docs/API.md.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest request, String? body) _handler;
  final List<(String method, String path, String? body)> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    String? body;
    if (request is http.Request) body = request.body;
    requests.add((request.method, request.url.path, body));
    return _handler(request, body);
  }
}

http.StreamedResponse _json(int status, Object data) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), status, headers: {'content-type': 'application/json'});

void main() {
  late AppDatabase db;
  late ServerSyncPrefs prefs;

  setUp(() async {
    db = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    prefs = ServerSyncPrefs(await SharedPreferences.getInstance(), MemorySecretStore());
    await prefs.setCredentials(serverUrl: 'https://servidor.ejemplo', apiKey: 'test-key');
  });
  tearDown(() => db.close());

  test('push envía sólo lo cambiado desde el último cursor y avanza el cursor', () async {
    final movements = DriftMovementRepository(db);
    await movements.add(MovementInput(
      type: TxType.expense,
      amountMinor: 50000,
      categoryId: 'exp_food',
      accountId: kDefaultAccountId,
      occurredAt: DateTime(2026, 9, 1),
      note: 'Cena',
    ));

    final fake = _FakeHttpClient((request, body) async {
      if (request.method == 'POST') return _json(200, {'serverTimeMs': 123456});
      return _json(200, {'serverTimeMs': 123456, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []});
    });
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);

    await service.syncNow();

    expect(prefs.lastPushedAt, 123456);
    final pushCall = fake.requests.firstWhere((r) => r.$1 == 'POST');
    final sent = jsonDecode(pushCall.$3!) as Map<String, dynamic>;
    expect((sent['transactions'] as List).any((t) => t['note'] == 'Cena'), isTrue);
    // Lo sembrado por seedDefaults (cuentas/categorías) también viaja la
    // primera vez, porque nunca se había subido nada (cursor en 0).
    expect((sent['accounts'] as List), isNotEmpty);
  });

  test('no manda nada si no hay cambios desde el último push', () async {
    await prefs.setLastPushedAt(DateTime.now().millisecondsSinceEpoch + 1000000); // "ya subí todo, incluso del futuro"
    var postCalls = 0;
    final fake = _FakeHttpClient((request, body) async {
      if (request.method == 'POST') {
        postCalls++;
        return _json(200, {'serverTimeMs': 1});
      }
      return _json(200, {'serverTimeMs': 1, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []});
    });
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);
    await service.syncNow();
    expect(postCalls, 0);
  });

  test('pull aplica movimientos nuevos del servidor (p. ej. registrados por el servicio externo) a la base local', () async {
    final fake = _FakeHttpClient((request, body) async {
      if (request.method == 'POST') return _json(200, {'serverTimeMs': 1});
      return _json(200, {
        'serverTimeMs': 999,
        'accounts': [],
        'categories': [],
        'transactions': [
          {
            'id': 'from-meta-ai',
            'type': 'expense',
            'amountMinor': 75000,
            'categoryId': 'exp_food',
            'accountId': kDefaultAccountId,
            'note': 'Registrado por el servicio externo',
            'occurredAt': DateTime(2026, 9, 10).millisecondsSinceEpoch,
            'createdAt': 1,
            'updatedAt': 1,
            'deletedAt': null,
          },
        ],
        'budgets': [],
      });
    });
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);

    await service.syncNow();

    final movements = DriftMovementRepository(db);
    final m = await movements.getById('from-meta-ai');
    expect(m, isNotNull);
    expect(m!.amountMinor, 75000);
    expect(m.note, 'Registrado por el servicio externo');
    expect(prefs.lastPulledAt, 999);
  });

  test('fullResync resetea los cursores antes de sincronizar', () async {
    await prefs.setLastPulledAt(500);
    await prefs.setLastPushedAt(500);
    final fake = _FakeHttpClient((request, body) async {
      if (request.method == 'POST') return _json(200, {'serverTimeMs': 10});
      return _json(200, {'serverTimeMs': 10, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []});
    });
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);

    await service.fullResync();

    // Tras un resync, el cursor refleja la respuesta del servidor, no quedó
    // en el valor viejo (500) ni se saltó por error.
    expect(prefs.lastPulledAt, 10);
    expect(prefs.lastPushedAt, 10);
  });

  test('un error del servidor se propaga como ServerSyncException', () async {
    final fake = _FakeHttpClient((request, body) async => _json(401, {'error': 'API key inválida.'}));
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);
    await expectLater(service.syncNow(), throwsA(isA<ServerSyncException>()));
  });

  test('si el servidor perdió su base (cambia su epoch), se vuelve a subir todo una sola vez', () async {
    await DriftMovementRepository(db).add(MovementInput(
      type: TxType.expense,
      amountMinor: 123400,
      categoryId: 'exp_food',
      accountId: kDefaultAccountId,
      occurredAt: DateTime(2026, 10, 2),
      note: 'Gasolina',
    ));

    final serverNow = DateTime.now().millisecondsSinceEpoch + 60000; // hora del servidor posterior a lo ya guardado
    var epoch = 'A';
    final fake = _FakeHttpClient((request, body) async {
      if (request.method == 'POST') return _json(200, {'serverTimeMs': serverNow});
      return _json(200, {'serverTimeMs': serverNow, 'epoch': epoch, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []});
    });
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);
    int pushes() => fake.requests.where((r) => r.$1 == 'POST').length;
    bool lastPushHasMovement() => fake.requests.lastWhere((r) => r.$1 == 'POST').$3!.contains('Gasolina');

    await service.syncNow();
    expect(pushes(), 1); // primera vez: sube lo que hay
    expect(prefs.serverEpoch, 'A');

    await service.syncNow();
    expect(pushes(), 1); // sin cambios y mismo servidor: no reenvía nada

    epoch = 'B'; // Render recreó el contenedor: base nueva y vacía
    await service.syncNow();
    expect(pushes(), 2); // se reinician los cursores y se sube todo otra vez
    expect(lastPushHasMovement(), isTrue);
    expect(prefs.serverEpoch, 'B');

    await service.syncNow();
    expect(pushes(), 2); // y no entra en bucle: ya está al día con la base nueva
  });

  test('un servidor antiguo sin epoch no provoca reenvíos', () async {
    await DriftMovementRepository(db).add(MovementInput(
      type: TxType.expense, amountMinor: 100, categoryId: 'exp_food', accountId: kDefaultAccountId, occurredAt: DateTime(2026, 10, 2)));
    final serverNow = DateTime.now().millisecondsSinceEpoch + 60000;
    final fake = _FakeHttpClient((request, body) async => request.method == 'POST'
        ? _json(200, {'serverTimeMs': serverNow})
        : _json(200, {'serverTimeMs': serverNow, 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []}));
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);
    await service.syncNow();
    await service.syncNow();
    expect(fake.requests.where((r) => r.$1 == 'POST').length, 1);
    expect(prefs.serverEpoch, isNull);
  });

  test('primer despliegue con epoch: si la app ya había sincronizado, vuelve a subir todo', () async {
    await DriftMovementRepository(db).add(MovementInput(
      type: TxType.expense, amountMinor: 100, categoryId: 'exp_food', accountId: kDefaultAccountId, occurredAt: DateTime(2026, 10, 2), note: 'Previo'));
    final serverNow = DateTime.now().millisecondsSinceEpoch + 60000;
    var withEpoch = false;
    final fake = _FakeHttpClient((request, body) async => request.method == 'POST'
        ? _json(200, {'serverTimeMs': serverNow})
        : _json(200, {'serverTimeMs': serverNow, if (withEpoch) 'epoch': 'NUEVA', 'accounts': [], 'categories': [], 'transactions': [], 'budgets': []}));
    final service = ServerSyncService(db, ServerSyncClient(httpClient: fake), prefs);
    int pushes() => fake.requests.where((r) => r.$1 == 'POST').length;

    await service.syncNow(); // servidor antiguo, sin epoch
    expect(pushes(), 1);
    withEpoch = true; // se despliega la versión nueva sobre un contenedor vacío
    await service.syncNow();
    expect(pushes(), 2);
    expect(fake.requests.lastWhere((r) => r.$1 == 'POST').$3, contains('Previo'));
    expect(prefs.serverEpoch, 'NUEVA');
    await service.syncNow();
    expect(pushes(), 2);
  });
}
