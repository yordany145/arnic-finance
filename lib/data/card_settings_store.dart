import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/card_config.dart';

/// Copia local de la configuración de las tarjetas (funciona sin internet). El servidor guarda la
/// misma información para que el puente de correo la lea; ver `ServerSyncService`.
class CardSettingsStore {
  CardSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'card_settings_v1';

  CardSettings read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const CardSettings();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CardSettings.fromServerConfig(json['config'] as Map<String, dynamic>? ?? const {}, json['updatedAt'] as int? ?? 0);
    } on Object {
      return const CardSettings(); // dato local dañado: se parte de cero y el servidor lo repone al sincronizar
    }
  }

  Future<void> write(CardSettings settings) => _prefs.setString(_key, jsonEncode({'updatedAt': settings.updatedAt, 'config': settings.toServerConfig()}));
}
