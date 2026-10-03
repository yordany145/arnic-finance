import 'dart:convert';
import 'dart:io';

import 'package:arnic_finance/data/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _apkUrl = 'https://github.com/yordany145/arnic-finance/releases/download/v0.2.0/arnic-finance.apk';

String _manifest({int build = 5, String? url, String? hash}) => jsonEncode({
      'versionName': '0.2.0',
      'buildNumber': build,
      'apkUrl': url ?? _apkUrl,
      'sha256': hash ?? 'a' * 64,
      'notes': 'Mejoras',
    });

void main() {
  group('check', () {
    UpdateService serviceReturning(http.Response Function(http.Request) handler) =>
        UpdateService(httpClient: MockClient((req) async => handler(req)), latestUrl: Uri.parse('https://example.test/latest.json'));

    test('hay versión más nueva: devuelve la información', () async {
      final info = await serviceReturning((_) => http.Response(_manifest(build: 5), 200)).check(2);
      expect(info?.versionName, '0.2.0');
      expect(info?.buildNumber, 5);
      expect(info?.notes, 'Mejoras');
    });

    test('misma versión o una más nueva instalada: null', () async {
      expect(await serviceReturning((_) => http.Response(_manifest(build: 5), 200)).check(5), isNull);
      expect(await serviceReturning((_) => http.Response(_manifest(build: 5), 200)).check(9), isNull);
    });

    test('rechaza un APK que no sea del repositorio de la app', () async {
      final s = serviceReturning((_) => http.Response(_manifest(url: 'https://evil.example/app.apk'), 200));
      expect(s.check(1), throwsA(isA<UpdateException>()));
      final s2 = serviceReturning((_) => http.Response(_manifest(url: 'http://github.com/yordany145/arnic-finance/releases/download/x.apk'), 200));
      expect(s2.check(1), throwsA(isA<UpdateException>()));
    });

    test('rechaza huella mal formada, JSON roto y campos faltantes', () async {
      expect(serviceReturning((_) => http.Response(_manifest(hash: 'zz'), 200)).check(1), throwsA(isA<UpdateException>()));
      expect(serviceReturning((_) => http.Response('no es json', 200)).check(1), throwsA(isA<UpdateException>()));
      expect(serviceReturning((_) => http.Response('{"versionName":"1"}', 200)).check(1), throwsA(isA<UpdateException>()));
    });

    test('404: mensaje claro de que no hay versión publicada', () async {
      expect(
        serviceReturning((_) => http.Response('', 404)).check(1),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('ninguna versión'))),
      );
    });
  });

  group('download', () {
    late Directory dir;
    final bytes = utf8.encode('contenido-falso-de-un-apk' * 1000);

    setUp(() => dir = Directory.systemTemp.createTempSync('arnic_update_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    UpdateInfo infoWith(String hash) => UpdateInfo(versionName: '0.2.0', buildNumber: 5, apkUrl: _apkUrl, sha256: hash);

    test('hash correcto: guarda el archivo y reporta progreso', () async {
      final service = UpdateService(httpClient: MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length)));
      final progress = <double>[];

      final file = await service.download(infoWith(sha256.convert(bytes).toString()), dir, onProgress: progress.add);

      expect(await file.readAsBytes(), bytes);
      expect(progress.last, 1.0);
    });

    test('hash distinto: borra el archivo y falla (no se instala nada sin verificar)', () async {
      final service = UpdateService(httpClient: MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length)));

      await expectLater(service.download(infoWith('b' * 64), dir), throwsA(isA<UpdateException>()));

      expect(dir.listSync(), isEmpty);
    });

    test('descarga interrumpida: no deja un archivo a medias', () async {
      final service = UpdateService(
        httpClient: MockClient.streaming((req, _) async {
          Stream<List<int>> broken() async* {
            yield bytes.sublist(0, 100);
            throw const SocketException('se cortó');
          }

          return http.StreamedResponse(broken(), 200, contentLength: bytes.length);
        }),
      );

      await expectLater(service.download(infoWith(sha256.convert(bytes).toString()), dir), throwsA(isA<UpdateException>()));

      expect(dir.listSync(), isEmpty);
    });

    test('HTTP de error: falla sin dejar archivo', () async {
      final service = UpdateService(httpClient: MockClient.streaming((req, _) async => http.StreamedResponse(const Stream.empty(), 404)));

      await expectLater(service.download(infoWith('a' * 64), dir), throwsA(isA<UpdateException>()));

      expect(dir.listSync(), isEmpty);
    });
  });
}
