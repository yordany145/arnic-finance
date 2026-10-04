import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'package:arnic_finance_server/db/database.dart';
import 'package:arnic_finance_server/server.dart';
import 'package:arnic_finance_server/util/rate_limit.dart';
import 'package:arnic_finance_server/util/seed_key.dart';
import 'package:crypto/crypto.dart';

const _setupToken = 'test-setup-token';

void main() {
  late ServerDatabase db;
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    db = ServerDatabase.inMemory();
    final handler = buildHandler(db, setupToken: _setupToken);
    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    await db.close();
  });

  Future<http.Response> post(String path, {Map<String, String>? headers, Object? body}) =>
      http.post(Uri.parse('$baseUrl$path'), headers: headers, body: body == null ? null : jsonEncode(body));
  Future<http.Response> get(String path, {Map<String, String>? headers}) =>
      http.get(Uri.parse('$baseUrl$path'), headers: headers);

  Future<String> setupAndGetApiKey() async {
    final res = await post('/v1/setup', headers: {'x-setup-token': _setupToken});
    expect(res.statusCode, 201);
    return (jsonDecode(res.body) as Map<String, dynamic>)['apiKey'] as String;
  }

  group('salud y setup', () {
    test('GET /health no requiere autenticación', () async {
      final res = await get('/health');
      expect(res.statusCode, 200);
    });

    test('setup sin X-Setup-Token: 401', () async {
      final res = await post('/v1/setup');
      expect(res.statusCode, 401);
    });

    test('setup con token incorrecto: 401', () async {
      final res = await post('/v1/setup', headers: {'x-setup-token': 'incorrecto'});
      expect(res.statusCode, 401);
    });

    test('setup dos veces sin rotate: 409, la key original sigue sirviendo', () async {
      final apiKey = await setupAndGetApiKey();
      final again = await post('/v1/setup', headers: {'x-setup-token': _setupToken});
      expect(again.statusCode, 409);

      final res = await get('/v1/categories', headers: {'authorization': 'Bearer $apiKey'});
      expect(res.statusCode, 200);
    });

    test('rotate: true invalida la key anterior', () async {
      final oldKey = await setupAndGetApiKey();
      final rotated = await post('/v1/setup', headers: {'x-setup-token': _setupToken}, body: {'rotate': true});
      expect(rotated.statusCode, 200);
      final newKey = (jsonDecode(rotated.body) as Map<String, dynamic>)['apiKey'] as String;
      expect(newKey, isNot(oldKey));

      expect((await get('/v1/categories', headers: {'authorization': 'Bearer $oldKey'})).statusCode, 401);
      expect((await get('/v1/categories', headers: {'authorization': 'Bearer $newKey'})).statusCode, 200);
    });
  });

  group('limitador de /v1/setup', () {
    test('cambiar el primer valor de X-Forwarded-For NO evita el límite (se usa la IP que añade el proxy)', () async {
      var limited = 0;
      for (var i = 0; i < 8; i++) {
        final res = await post('/v1/setup', headers: {'x-setup-token': 'mal$i', 'x-forwarded-for': 'falsa-$i, 203.0.113.9'});
        if (res.statusCode == 429) limited++;
      }
      expect(limited, greaterThan(0));
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('ab', 'abc'), isFalse);
      expect(constantTimeEquals('abcd', 'abc'), isFalse);
      expect(constantTimeEquals(null, 'abc'), isFalse);
    });
  });

  group('configuración de tarjetas', () {
    Future<http.Response> put(String key, Object body) => http.put(Uri.parse('$baseUrl/v1/config'),
        headers: {'authorization': 'Bearer $key'}, body: jsonEncode(body));

    test('sin configuración: vacía y updatedAt 0', () async {
      final key = await setupAndGetApiKey();
      final res = await get('/v1/config', headers: {'authorization': 'Bearer $key'});
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body), {'updatedAt': 0, 'config': <String, Object?>{}});
    });

    test('guardar y leer; una escritura más vieja da 409 y no pisa la nueva', () async {
      final key = await setupAndGetApiKey();
      final cards = {'cards': [{'accountId': 'a1', 'limitMinor': 1500000, 'cutDay': 15, 'dueDay': 5}]};
      expect((await put(key, {'config': cards, 'updatedAt': 2000})).statusCode, 200);

      final stale = await put(key, {'config': {'cards': []}, 'updatedAt': 1000});
      expect(stale.statusCode, 409);
      expect(jsonDecode(stale.body)['updatedAt'], 2000);

      final read = jsonDecode((await get('/v1/config', headers: {'authorization': 'Bearer $key'})).body);
      expect(read, {'updatedAt': 2000, 'config': cards});
    });

    test('rechaza días fuera de 1–31, límites negativos, tarjetas repetidas y cuerpos mal formados', () async {
      final key = await setupAndGetApiKey();
      Future<int> status(Object cards) async => (await put(key, {'config': {'cards': cards}, 'updatedAt': 5000})).statusCode;
      expect(await status([{'accountId': 'a', 'cutDay': 32}]), 400);
      expect(await status([{'accountId': 'a', 'dueDay': 0}]), 400);
      expect(await status([{'accountId': 'a', 'limitMinor': -1}]), 400);
      expect(await status([{'accountId': 'a'}, {'accountId': 'a'}]), 400);
      expect(await status([{'limitMinor': 5}]), 400);
      expect(await status('no es lista'), 400);
      expect((await put(key, {'config': 'x', 'updatedAt': 5000})).statusCode, 400);
      expect((await put(key, {'config': {}, 'updatedAt': 'ayer'})).statusCode, 400);
      expect(await status([{'accountId': 'a', 'limitMinor': null, 'cutDay': null, 'dueDay': 31}]), 200);
    });

    test('exige API key', () async {
      expect((await get('/v1/config')).statusCode, 401);
    });
  });

  group('clave que sobrevive a una base nueva (API_KEY_HASH) y epoch', () {
    String hashOf(String key) => sha256.convert(utf8.encode(key)).toString();

    test('base vacía + hash: la clave funciona sin haber pasado por /v1/setup', () async {
      expect(await seedApiKeyHash(db, hashOf('mi-clave-secreta')), isTrue);
      final res = await get('/v1/categories', headers: {'authorization': 'Bearer mi-clave-secreta'});
      expect(res.statusCode, isNot(401));
      final wrong = await get('/v1/categories', headers: {'authorization': 'Bearer otra'});
      expect(wrong.statusCode, 401);
    });

    test('nunca pisa un usuario existente, y un hash mal formado se rechaza', () async {
      final existing = await setupAndGetApiKey();
      expect(await seedApiKeyHash(db, hashOf('otra-clave')), isFalse);
      expect((await get('/v1/categories', headers: {'authorization': 'Bearer $existing'})).statusCode, isNot(401));
      expect(await seedApiKeyHash(db, null), isFalse);
      expect(await seedApiKeyHash(db, '  '), isFalse);
      expect(() => seedApiKeyHash(db, 'no-es-un-hash'), throwsFormatException);
    });

    test('con la clave sembrada, /v1/setup sin rotate sigue dando 409 (no se crea una segunda)', () async {
      await seedApiKeyHash(db, hashOf('mi-clave-secreta'));
      final res = await post('/v1/setup', headers: {'x-setup-token': _setupToken});
      expect(res.statusCode, 409);
    });

    test('el epoch es estable en una base y distinto en una base nueva; viaja en /v1/sync', () async {
      final key = await setupAndGetApiKey();
      final a = jsonDecode((await get('/v1/sync?since=0', headers: {'authorization': 'Bearer $key'})).body)['epoch'] as String;
      final b = jsonDecode((await get('/v1/sync?since=0', headers: {'authorization': 'Bearer $key'})).body)['epoch'] as String;
      expect(a, b);
      final other = ServerDatabase.inMemory();
      addTearDown(other.close);
      expect(await other.epoch(), isNot(a));
    });
  });

  group('autenticación de rutas protegidas', () {
    test('sin Authorization: 401', () async {
      expect((await get('/v1/categories')).statusCode, 401);
    });

    test('con una key inventada: 401', () async {
      final res = await get('/v1/categories', headers: {'authorization': 'Bearer no-existe'});
      expect(res.statusCode, 401);
    });
  });

  group('sincronización (push del teléfono, luego lectura)', () {
    test('push y pull reproducen los mismos datos, sin exponer userId', () async {
      final apiKey = await setupAndGetApiKey();
      final auth = {'authorization': 'Bearer $apiKey'};
      final now = DateTime.now().millisecondsSinceEpoch;

      final push = await post('/v1/sync', headers: auth, body: {
        'accounts': [
          {'id': 'acc_cash', 'name': 'Efectivo', 'icon': '💵', 'kind': 'cash', 'sortOrder': 0, 'createdAt': now, 'updatedAt': now, 'deletedAt': null},
        ],
        'categories': [
          {
            'id': 'exp_food',
            'name': 'Comida',
            'icon': '🍔',
            'type': 'expense',
            'sortOrder': 0,
            'createdAt': now,
            'updatedAt': now,
            'deletedAt': null,
          },
        ],
        'transactions': [
          {
            'id': 'tx1',
            'type': 'expense',
            'amountMinor': 50000,
            'categoryId': 'exp_food',
            'accountId': 'acc_cash',
            'note': 'Almuerzo',
            'occurredAt': now,
            'createdAt': now,
            'updatedAt': now,
            'deletedAt': null,
          },
        ],
        'budgets': <Object>[],
      });
      expect(push.statusCode, 200);

      final pull = await get('/v1/sync?since=0', headers: auth);
      expect(pull.statusCode, 200);
      final pulled = jsonDecode(pull.body) as Map<String, dynamic>;
      expect((pulled['transactions'] as List).single['note'], 'Almuerzo');
      expect((pulled['accounts'] as List).single, isNot(contains('userId')));

      // Un segundo pull con `since` = ahora no debe repetir nada.
      final secondPull = await get('/v1/sync?since=${pulled['serverTimeMs']}', headers: auth);
      final secondBody = jsonDecode(secondPull.body) as Map<String, dynamic>;
      expect(secondBody['transactions'], isEmpty);
    });

    test('push rechaza un kind/type inválido', () async {
      final apiKey = await setupAndGetApiKey();
      final res = await post('/v1/sync', headers: {'authorization': 'Bearer $apiKey'}, body: {
        'accounts': [
          {'id': 'a1', 'name': 'X', 'icon': '💵', 'kind': 'no-es-un-tipo-valido', 'createdAt': 0, 'updatedAt': 0},
        ],
      });
      expect(res.statusCode, 400);
    });
  });

  group('registrar un movimiento (lo que llamaría el servicio externo)', () {
    Future<String> setupWithSeed() async {
      final apiKey = await setupAndGetApiKey();
      final now = DateTime.now().millisecondsSinceEpoch;
      await post('/v1/sync', headers: {'authorization': 'Bearer $apiKey'}, body: {
        'accounts': [
          {'id': 'acc_cash', 'name': 'Efectivo', 'icon': '💵', 'kind': 'cash', 'sortOrder': 0, 'createdAt': now, 'updatedAt': now},
        ],
        'categories': [
          {'id': 'exp_food', 'name': 'Comida', 'icon': '🍔', 'type': 'expense', 'sortOrder': 0, 'createdAt': now, 'updatedAt': now},
          {'id': 'exp_fuel', 'name': 'Combustible', 'icon': '⛽', 'type': 'expense', 'sortOrder': 1, 'createdAt': now, 'updatedAt': now},
        ],
      });
      return apiKey;
    }

    test('con amountMinor y categoría exacta', () async {
      final apiKey = await setupWithSeed();
      final res = await post('/v1/movements', headers: {'authorization': 'Bearer $apiKey'}, body: {
        'type': 'expense',
        'amountMinor': 35000,
        'category': 'Comida',
      });
      expect(res.statusCode, 201);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['amountMinor'], 35000);
      expect(body['account'], 'Efectivo'); // cuenta por defecto: no se indicó ninguna
    });

    test('con amount en unidades (no centavos)', () async {
      final apiKey = await setupWithSeed();
      final res = await post('/v1/movements', headers: {'authorization': 'Bearer $apiKey'}, body: {
        'type': 'expense',
        'amount': 350.0,
        'category': 'comida', // minúsculas: debe igual resolver
      });
      expect(res.statusCode, 201);
      expect((jsonDecode(res.body) as Map<String, dynamic>)['amountMinor'], 35000);
    });

    test('categoría que no existe: 422 con sugerencias, no crea nada', () async {
      final apiKey = await setupWithSeed();
      final res = await post('/v1/movements', headers: {'authorization': 'Bearer $apiKey'}, body: {
        'type': 'expense',
        'amount': 100,
        'category': 'Mascotas',
      });
      expect(res.statusCode, 422);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['suggestions'], containsAll(['Comida', 'Combustible']));

      final list = await get('/v1/movements', headers: {'authorization': 'Bearer $apiKey'});
      expect(jsonDecode(list.body), isEmpty);
    });

    test('sin monto: 400', () async {
      final apiKey = await setupWithSeed();
      final res = await post('/v1/movements', headers: {'authorization': 'Bearer $apiKey'}, body: {'type': 'expense', 'category': 'Comida'});
      expect(res.statusCode, 400);
    });

    test('sin cuentas sincronizadas todavía: 409 (no inventa una cuenta)', () async {
      final apiKey = await setupAndGetApiKey(); // sin seed
      final res = await post('/v1/movements', headers: {'authorization': 'Bearer $apiKey'}, body: {
        'type': 'expense',
        'amount': 100,
        'category': 'Comida',
      });
      expect(res.statusCode, 409);
    });
  });

  group('lectura: movimientos, resumen, categorías, cuentas', () {
    test('resumen separa ingresos y gastos, balance es la resta', () async {
      final apiKey = await setupAndGetApiKey();
      final auth = {'authorization': 'Bearer $apiKey'};
      final now = DateTime.now().millisecondsSinceEpoch;
      await post('/v1/sync', headers: auth, body: {
        'accounts': [
          {'id': 'acc_cash', 'name': 'Efectivo', 'icon': '💵', 'kind': 'cash', 'createdAt': now, 'updatedAt': now},
        ],
        'categories': [
          {'id': 'exp_food', 'name': 'Comida', 'icon': '🍔', 'type': 'expense', 'createdAt': now, 'updatedAt': now},
          {'id': 'inc_salary', 'name': 'Salario', 'icon': '💰', 'type': 'income', 'createdAt': now, 'updatedAt': now},
        ],
        'transactions': [
          {'id': 't1', 'type': 'expense', 'amountMinor': 30000, 'categoryId': 'exp_food', 'accountId': 'acc_cash', 'occurredAt': now, 'createdAt': now, 'updatedAt': now},
          {'id': 't2', 'type': 'income', 'amountMinor': 200000, 'categoryId': 'inc_salary', 'accountId': 'acc_cash', 'occurredAt': now, 'createdAt': now, 'updatedAt': now},
        ],
      });

      final res = await get('/v1/summary', headers: auth);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['incomeMinor'], 200000);
      expect(body['expenseMinor'], 30000);
      expect(body['balanceMinor'], 170000);
    });

    test('categorías filtra por type', () async {
      final apiKey = await setupAndGetApiKey();
      final auth = {'authorization': 'Bearer $apiKey'};
      final now = DateTime.now().millisecondsSinceEpoch;
      await post('/v1/sync', headers: auth, body: {
        'categories': [
          {'id': 'exp_food', 'name': 'Comida', 'icon': '🍔', 'type': 'expense', 'createdAt': now, 'updatedAt': now},
          {'id': 'inc_salary', 'name': 'Salario', 'icon': '💰', 'type': 'income', 'createdAt': now, 'updatedAt': now},
        ],
      });
      final res = await get('/v1/categories?type=income', headers: auth);
      final list = jsonDecode(res.body) as List;
      expect(list, hasLength(1));
      expect(list.single['name'], 'Salario');
    });
  });
}
