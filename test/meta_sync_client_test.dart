import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arnic_finance/data/meta_sync_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) _handler;
  final List<Uri> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url);
    return _handler(request);
  }
}

http.StreamedResponse _json(int status, Object data) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), status, headers: {'content-type': 'application/json'});

void main() {
  group('normalización de la URL del servidor', () {
    test('sin esquema: asume https', () async {
      final fake = _FakeHttpClient((r) => _json(200, {'apiKey': 'k'}));
      final client = MetaSyncClient(httpClient: fake);
      await client.setup(serverUrl: 'arnic-finance-api.onrender.com', setupToken: 't');
      expect(fake.requestedUrls.single.toString(), 'https://arnic-finance-api.onrender.com/v1/setup');
    });

    test('con barra final: se quita antes de concatenar la ruta', () async {
      final fake = _FakeHttpClient((r) => _json(200, {'apiKey': 'k'}));
      final client = MetaSyncClient(httpClient: fake);
      await client.setup(serverUrl: 'https://servidor.com/', setupToken: 't');
      expect(fake.requestedUrls.single.toString(), 'https://servidor.com/v1/setup');
    });

    test('con espacios alrededor (copiar/pegar): se recortan', () async {
      final fake = _FakeHttpClient((r) => _json(200, {'apiKey': 'k'}));
      final client = MetaSyncClient(httpClient: fake);
      await client.setup(serverUrl: '  https://servidor.com  ', setupToken: 't');
      expect(fake.requestedUrls.single.toString(), 'https://servidor.com/v1/setup');
    });

    test('http:// explícito se respeta (no se fuerza a https)', () async {
      final fake = _FakeHttpClient((r) => _json(200, {'apiKey': 'k'}));
      final client = MetaSyncClient(httpClient: fake);
      await client.setup(serverUrl: 'http://localhost:8080', setupToken: 't');
      expect(fake.requestedUrls.single.toString(), 'http://localhost:8080/v1/setup');
    });
  });

  group('errores de red traducidos a MetaSyncException', () {
    test('timeout: mensaje explica que puede estar "despertando"', () async {
      final fake = _FakeHttpClient((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _json(200, {'apiKey': 'k'});
      });
      final client = MetaSyncClient(httpClient: fake, timeout: const Duration(milliseconds: 5));
      await expectLater(
        client.setup(serverUrl: 'https://servidor.com', setupToken: 't'),
        throwsA(isA<MetaSyncException>().having((e) => e.message, 'message', contains('despertando'))),
      );
    });

    test('SocketException: mensaje pide revisar internet/URL', () async {
      final fake = _FakeHttpClient((r) => throw const SocketException('fallo de red'));
      final client = MetaSyncClient(httpClient: fake);
      await expectLater(
        client.setup(serverUrl: 'https://servidor.com', setupToken: 't'),
        throwsA(isA<MetaSyncException>().having((e) => e.message, 'message', contains('internet'))),
      );
    });

    test('respuesta no-JSON (p. ej. página de error de Render): no revienta, da un mensaje genérico', () async {
      final fake = _FakeHttpClient((r) => http.StreamedResponse(Stream.value(utf8.encode('<html>502</html>')), 502));
      final client = MetaSyncClient(httpClient: fake);
      await expectLater(
        client.setup(serverUrl: 'https://servidor.com', setupToken: 't'),
        throwsA(isA<MetaSyncException>().having((e) => e.message, 'message', contains('502'))),
      );
    });
  });
}
