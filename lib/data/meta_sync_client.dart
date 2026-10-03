import 'dart:convert';

import 'package:http/http.dart' as http;

class MetaSyncException implements Exception {
  MetaSyncException(this.message);
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

/// Cliente HTTP del servidor opcional en `server/` (ver docs/API.md). Recibe
/// un `http.Client` inyectable para poder probarlo sin red real.
class MetaSyncClient {
  MetaSyncClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<String> setup({required String serverUrl, required String setupToken, bool rotate = false}) async {
    final res = await _http.post(
      Uri.parse('${_normalize(serverUrl)}/v1/setup'),
      headers: {'x-setup-token': setupToken, 'content-type': 'application/json'},
      body: jsonEncode({'rotate': rotate}),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['apiKey'] as String;
    }
    throw MetaSyncException(_errorMessage(res));
  }

  Future<PullResult> pull({required String serverUrl, required String apiKey, required int since}) async {
    final res = await _http.get(Uri.parse('${_normalize(serverUrl)}/v1/sync?since=$since'), headers: _authHeaders(apiKey));
    if (res.statusCode != 200) throw MetaSyncException(_errorMessage(res));
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
    final res = await _http.post(
      Uri.parse('${_normalize(serverUrl)}/v1/sync'),
      headers: _authHeaders(apiKey),
      body: jsonEncode(rows),
    );
    if (res.statusCode != 200) throw MetaSyncException(_errorMessage(res));
    return (jsonDecode(res.body) as Map<String, dynamic>)['serverTimeMs'] as int;
  }

  Map<String, String> _authHeaders(String apiKey) => {'authorization': 'Bearer $apiKey', 'content-type': 'application/json'};

  String _normalize(String serverUrl) => serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;

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
