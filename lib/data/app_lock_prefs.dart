import 'package:shared_preferences/shared_preferences.dart';

/// Si el bloqueo de la app está activado. Se guarda en `shared_preferences`
/// (no en `app_settings` de drift) a propósito: es una preferencia sólo de
/// este dispositivo/instalación, y el código nativo (Kotlin/Swift) no
/// necesita conocerla — la hoja de registro rápido ya exige desbloquear el
/// teléfono por su cuenta (ver `BaseQuickTileService`).
class AppLockPrefs {
  AppLockPrefs(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'app_lock_enabled';

  bool get enabled => _prefs.getBool(_key) ?? false;

  Future<void> setEnabled(bool value) => _prefs.setBool(_key, value);
}
