import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';

/// Configuración de la integración opcional con servicios externos (p. ej. un
/// conector de Meta IA) vía el servidor en `server/`. Apagada por defecto: si
/// `enabled` es `false`, el resto de la app sigue 100% local, igual que hoy.
/// Ver docs/API.md en la raíz del repo.
class MetaSyncPrefs {
  MetaSyncPrefs(this._prefs, this._secrets);

  final SharedPreferences _prefs;
  final SecretStore _secrets;

  /// La key vive en el [SecretStore] (Keystore), no en SharedPreferences (texto
  /// plano en disco). Se copia aquí al arrancar para que el getter siga siendo síncrono.
  String? _apiKey;

  static const _kEnabled = 'meta_sync_enabled';
  static const _kServerUrl = 'meta_sync_server_url';
  static const _kApiKey = 'meta_sync_api_key'; // misma clave en SharedPreferences (legado) y en el SecretStore
  static const _kLastPulledAt = 'meta_sync_last_pulled_at';
  static const _kLastPushedAt = 'meta_sync_last_pushed_at';

  bool get enabled => _prefs.getBool(_kEnabled) ?? false;
  Future<void> setEnabled(bool value) => _prefs.setBool(_kEnabled, value);

  String? get serverUrl => _prefs.getString(_kServerUrl);
  String? get apiKey => _apiKey;

  /// Llamar una vez al arrancar. Si hay una key guardada por versiones anteriores
  /// en SharedPreferences (texto plano), la mueve al Keystore y la borra de allí.
  Future<void> load() async {
    _apiKey = await _secrets.read(_kApiKey);
    final legacy = _prefs.getString(_kApiKey);
    if (legacy != null) {
      if (_apiKey == null) {
        await _secrets.write(_kApiKey, legacy);
        _apiKey = legacy;
      }
      await _prefs.remove(_kApiKey);
    }
  }

  bool get isConfigured => serverUrl != null && _apiKey != null;

  Future<void> setCredentials({required String serverUrl, required String apiKey}) async {
    // Un servidor nuevo/otra cuenta no comparte el historial de cursores del anterior.
    await _secrets.write(_kApiKey, apiKey);
    _apiKey = apiKey;
    await _prefs.setString(_kServerUrl, serverUrl);
    await resetCursors();
  }

  Future<void> clearCredentials() async {
    await _prefs.remove(_kServerUrl);
    await _secrets.delete(_kApiKey);
    _apiKey = null;
    await _prefs.setBool(_kEnabled, false);
    await resetCursors();
  }

  int get lastPulledAt => _prefs.getInt(_kLastPulledAt) ?? 0;
  Future<void> setLastPulledAt(int value) => _prefs.setInt(_kLastPulledAt, value);

  int get lastPushedAt => _prefs.getInt(_kLastPushedAt) ?? 0;
  Future<void> setLastPushedAt(int value) => _prefs.setInt(_kLastPushedAt, value);

  /// Para "forzar sincronización completa": la próxima vez se reenvía/relee todo.
  Future<void> resetCursors() async {
    await _prefs.remove(_kLastPulledAt);
    await _prefs.remove(_kLastPushedAt);
  }
}
