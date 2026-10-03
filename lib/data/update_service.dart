import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Repositorio del que la app se actualiza. Fijado en código a propósito: aunque
/// alguien manipulara `latest.json`, la app sólo descargaría APKs de este repo
/// (y Android, además, rechaza cualquier APK que no esté firmado con nuestra clave).
const kUpdateRepo = 'yordany145/arnic-finance';
final Uri kLatestJsonUrl = Uri.parse('https://github.com/$kUpdateRepo/releases/latest/download/latest.json');
const _allowedApkPrefix = 'https://github.com/$kUpdateRepo/releases/download/';

class UpdateInfo {
  const UpdateInfo({required this.versionName, required this.buildNumber, required this.apkUrl, required this.sha256, this.notes = ''});

  final String versionName;
  final int buildNumber;
  final String apkUrl;
  final String sha256;
  final String notes;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateService {
  UpdateService({http.Client? httpClient, Uri? latestUrl, this.timeout = const Duration(seconds: 30)})
      : _http = httpClient ?? http.Client(),
        _latestUrl = latestUrl ?? kLatestJsonUrl;

  final http.Client _http;
  final Uri _latestUrl;
  final Duration timeout;

  /// `null` si ya tienes la última versión (o una más nueva, p. ej. una compilación local).
  Future<UpdateInfo?> check(int currentBuild) async {
    final http.Response res;
    try {
      res = await _http.get(_latestUrl).timeout(timeout);
    } on SocketException {
      throw const UpdateException('Sin conexión a internet.');
    } on http.ClientException {
      throw const UpdateException('Sin conexión a internet.');
    } on Exception {
      throw const UpdateException('No se pudo consultar las actualizaciones. Intenta de nuevo.');
    }
    if (res.statusCode == 404) throw const UpdateException('Todavía no hay ninguna versión publicada.');
    if (res.statusCode != 200) throw UpdateException('El servidor de actualizaciones respondió ${res.statusCode}.');

    final info = parse(utf8.decode(res.bodyBytes));
    return info.buildNumber > currentBuild ? info : null;
  }

  static UpdateInfo parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const UpdateException('La información de la actualización no es válida.');
    }
    if (json is! Map<String, dynamic>) throw const UpdateException('La información de la actualización no es válida.');

    final versionName = json['versionName'];
    final buildNumber = json['buildNumber'];
    final apkUrl = json['apkUrl'];
    final hash = json['sha256'];
    if (versionName is! String || buildNumber is! int || apkUrl is! String || hash is! String) {
      throw const UpdateException('La información de la actualización está incompleta.');
    }
    if (!apkUrl.startsWith(_allowedApkPrefix)) throw const UpdateException('La actualización apunta a una dirección no permitida.');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) throw const UpdateException('La huella de la actualización no es válida.');
    return UpdateInfo(versionName: versionName, buildNumber: buildNumber, apkUrl: apkUrl, sha256: hash.toLowerCase(), notes: (json['notes'] as String?) ?? '');
  }

  /// Descarga el APK a [dir], comprobando su SHA-256 mientras llega. Si no
  /// coincide, borra el archivo y falla: nunca se entrega un APK sin verificar.
  Future<File> download(UpdateInfo info, Directory dir, {void Function(double progress)? onProgress}) async {
    final file = File('${dir.path}/arnic-finance-${info.buildNumber}.apk');
    if (await file.exists()) await file.delete();
    final sink = file.openWrite();
    final output = AccumulatorSink<Digest>();
    final hasher = sha256.startChunkedConversion(output);
    try {
      final res = await _http.send(http.Request('GET', Uri.parse(info.apkUrl))).timeout(timeout);
      if (res.statusCode != 200) throw UpdateException('No se pudo descargar la actualización (${res.statusCode}).');
      final total = res.contentLength ?? 0;
      var received = 0;
      await for (final chunk in res.stream.timeout(timeout)) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      hasher.close();
      await sink.close();
    } on UpdateException {
      await _discard(sink, file);
      rethrow;
    } on Exception {
      await _discard(sink, file);
      throw const UpdateException('Se interrumpió la descarga. Intenta de nuevo.');
    }
    if (output.events.single.toString() != info.sha256) {
      await file.delete();
      throw const UpdateException('El archivo descargado no coincide con la huella esperada. No se instaló.');
    }
    return file;
  }

  Future<void> _discard(IOSink sink, File file) async {
    try {
      await sink.close();
    } catch (_) {}
    if (await file.exists()) await file.delete();
  }

  void close() => _http.close();
}

/// Recoge el resultado de una conversión por trozos (`package:crypto` no trae uno).
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}
