import 'package:arnic_finance/data/meta_sync_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('apagado y sin configurar por defecto', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = MetaSyncPrefs(await SharedPreferences.getInstance());
    expect(prefs.enabled, isFalse);
    expect(prefs.isConfigured, isFalse);
  });

  test('guardar credenciales las deja listas y resetea los cursores', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = MetaSyncPrefs(await SharedPreferences.getInstance());
    await prefs.setLastPulledAt(123);
    await prefs.setCredentials(serverUrl: 'https://api.ejemplo.com', apiKey: 'clave123');

    expect(prefs.isConfigured, isTrue);
    expect(prefs.serverUrl, 'https://api.ejemplo.com');
    expect(prefs.apiKey, 'clave123');
    expect(prefs.lastPulledAt, 0); // se reseteó al cambiar de servidor
  });

  test('desconectar borra credenciales, apaga y resetea cursores', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = MetaSyncPrefs(await SharedPreferences.getInstance());
    await prefs.setCredentials(serverUrl: 'https://x.com', apiKey: 'k');
    await prefs.setEnabled(true);
    await prefs.setLastPushedAt(999);

    await prefs.clearCredentials();

    expect(prefs.isConfigured, isFalse);
    expect(prefs.enabled, isFalse);
    expect(prefs.lastPushedAt, 0);
  });
}
