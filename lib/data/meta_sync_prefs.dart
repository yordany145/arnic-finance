import 'package:shared_preferences/shared_preferences.dart';

/// Configuración de la integración opcional con servicios externos (p. ej. un
/// conector de Meta IA) vía el servidor en `server/`. Apagada por defecto: si
/// `enabled` es `false`, el resto de la app sigue 100% local, igual que hoy.
/// Ver docs/API.md en la raíz del repo.
class MetaSyncPrefs {
  MetaSyncPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _kEnabled = 'meta_sync_enabled';
  static const _kServerUrl = 'meta_sync_server_url';
  static const _kApiKey = 'meta_sync_api_key';
  static const _kLastPulledAt = 'meta_sync_last_pulled_at';
  static const _kLastPushedAt = 'meta_sync_last_pushed_at';

  bool get enabled => _prefs.getBool(_kEnabled) ?? false;
  Future<void> setEnabled(bool value) => _prefs.setBool(_kEnabled, value);

  String? get serverUrl => _prefs.getString(_kServerUrl);
  String? get apiKey => _prefs.getString(_kApiKey);

  bool get isConfigured => serverUrl != null && apiKey != null;

  Future<void> setCredentials({required String serverUrl, required String apiKey}) async {
    // Un servidor nuevo/otra cuenta no comparte el historial de cursores del anterior.
    await _prefs.setString(_kServerUrl, serverUrl);
    await _prefs.setString(_kApiKey, apiKey);
    await resetCursors();
  }

  Future<void> clearCredentials() async {
    await _prefs.remove(_kServerUrl);
    await _prefs.remove(_kApiKey);
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
