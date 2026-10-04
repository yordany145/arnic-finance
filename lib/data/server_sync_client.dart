import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ServerSyncException implements Exception {
  ServerSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

typedef SyncRows = Map<String, List<Map<String, dynamic>>>;

class PullResult {
  const PullResult({required this.serverTimeMs, required this.rows});
  final int serverTimeMs;
  final SyncRows rows;
}

class RemoteConfig {
  const RemoteConfig({required this.updatedAt, required this.config});
  final int updatedAt;
  final Map<String, dynamic> config;
}

/// Cliente HTTP del servidor opcional en `server/` (ver docs/API.md). Recibe
/// un `http.Client` inyectable para poder probarlo sin red real.
class ServerSyncClient {
  /// [timeout] es largo por defecto (ver comentario abajo) y sólo se acorta
  /// en tests; el código de producción nunca debería pasarlo.
  ///
  /// El plan gratis de Render "duerme" el servidor a los 15 min sin uso: la
  /// primera petición después puede tardar ~1 minuto en responder mientras
  /// arranca. Por eso el tiempo de espera es largo (no es un valor arbitrario):
  /// cortarlo antes confundiría "está despertando" con "no hay conexión".
  ServerSyncClient({http.Client? httpClient, this.timeout = const Duration(seconds: 70)}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  Future<String> setup({required String serverUrl, required String setupToken, bool rotate = false}) async {
    final res = await _send(() => _http.post(
          Uri.parse('${_normalize(serverUrl)}/v1/setup'),
          headers: {'x-setup-token': setupToken, 'content-type': 'application/json'},
          body: jsonEncode({'rotate': rotate}),
        ));
    if (res.statusCode == 200 || res.statusCode == 201) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['apiKey'] as String;
    }
    throw ServerSyncException(_errorMessage(res));
  }

  Future<PullResult> pull({required String serverUrl, required String apiKey, required int since}) async {
    final res = await _send(
      () => _http.get(Uri.parse('${_normalize(serverUrl)}/v1/sync?since=$since'), headers: _authHeaders(apiKey)),
    );
    if (res.statusCode != 200) throw ServerSyncException(_errorMessage(res));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PullResult(
      serverTimeMs: body['serverTimeMs'] as int,
      rows: {
        for (final key in const ['accounts', 'categories', 'transactions', 'budgets'])
          key: (body[key] as List? ?? const []).cast<Map<String, dynamic>>(),
      },
    );
  }

  Future<int> push({required String serverUrl, required String apiKey, required SyncRows rows}) async {
    final res = await _send(
      () => _http.post(Uri.parse('${_normalize(serverUrl)}/v1/sync'), headers: _authHeaders(apiKey), body: jsonEncode(rows)),
    );
    if (res.statusCode != 200) throw ServerSyncException(_errorMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['serverTimeMs'] as int;
  }

  /// Configuración guardada en el servidor (tarjetas). `null` si el servidor es una versión anterior sin `/v1/config`.
  Future<RemoteConfig?> getConfig({required String serverUrl, required String apiKey}) async {
    final res = await _send(() => _http.get(Uri.parse('${_normalize(serverUrl)}/v1/config'), headers: _authHeaders(apiKey)));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw ServerSyncException(_errorMessage(res));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return RemoteConfig(updatedAt: body['updatedAt'] as int? ?? 0, config: (body['config'] as Map?)?.cast<String, dynamic>() ?? const {});
  }

  /// `true` si el servidor la guardó; `false` si ya tenía una más reciente (409).
  Future<bool> putConfig({required String serverUrl, required String apiKey, required Map<String, dynamic> config, required int updatedAt}) async {
    final res = await _send(() => _http.put(
          Uri.parse('${_normalize(serverUrl)}/v1/config'),
          headers: _authHeaders(apiKey),
          body: jsonEncode({'config': config, 'updatedAt': updatedAt}),
        ));
    if (res.statusCode == 200) return true;
    if (res.statusCode == 409 || res.statusCode == 404) return false;
    throw ServerSyncException(_errorMessage(res));
  }

  /// Centraliza el timeout y traduce los errores de red/DNS/certificado a un
  /// mensaje en español entendible, en vez de dejar escapar la excepción
  /// cruda de `dart:io` hasta la UI.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw ServerSyncException(
        'El servidor no respondió a tiempo. Si llevaba un rato sin usarse puede estar "despertando" (plan gratis de Render) — intenta de nuevo en un minuto.',
      );
    } on SocketException {
      throw ServerSyncException('No se pudo conectar. Revisa tu internet y que la URL del servidor sea correcta.');
    } on HandshakeException {
      throw ServerSyncException('No se pudo establecer una conexión segura (HTTPS) con ese servidor. Revisa la URL.');
    } on FormatException {
      throw ServerSyncException('La URL del servidor no es válida.');
    }
  }

  Map<String, String> _authHeaders(String apiKey) => {'authorization': 'Bearer $apiKey', 'content-type': 'application/json'};

  /// Quita espacios y la barra final, y asume `https://` si no se escribió
  /// ningún esquema (lo más común al copiar sólo el dominio).
  String _normalize(String serverUrl) {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } on FormatException {
      // cuerpo no era JSON: se usa el mensaje genérico de abajo.
    }
    return 'El servidor respondió con un error (${res.statusCode}).';
  }

  void close() => _http.close();
}
