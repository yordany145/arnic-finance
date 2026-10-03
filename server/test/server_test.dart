import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'package:arnic_finance_server/db/database.dart';
import 'package:arnic_finance_server/server.dart';

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

  group('registrar un movimiento (lo que llamaría Meta IA)', () {
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
