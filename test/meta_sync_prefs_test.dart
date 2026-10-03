import 'package:arnic_finance/data/meta_sync_prefs.dart';
import 'package:arnic_finance/data/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('apagado y sin configurar por defecto', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = MetaSyncPrefs(await SharedPreferences.getInstance(), MemorySecretStore());
    expect(prefs.enabled, isFalse);
    expect(prefs.isConfigured, isFalse);
  });

  test('guardar credenciales las deja listas y resetea los cursores', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = MetaSyncPrefs(await SharedPreferences.getInstance(), MemorySecretStore());
    await prefs.setLastPulledAt(123);
    await prefs.setCredentials(serverUrl: 'https://api.ejemplo.com', apiKey: 'clave123');

    expect(prefs.isConfigured, isTrue);
    expect(prefs.serverUrl, 'https://api.ejemplo.com');
    expect(prefs.apiKey, 'clave123');
    expect(prefs.lastPulledAt, 0); // se reseteó al cambiar de servidor
  });

  test('desconectar borra credenciales, apaga y resetea cursores', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = MetaSyncPrefs(await SharedPreferences.getInstance(), MemorySecretStore());
    await prefs.setCredentials(serverUrl: 'https://x.com', apiKey: 'k');
    await prefs.setEnabled(true);
    await prefs.setLastPushedAt(999);

    await prefs.clearCredentials();

    expect(prefs.isConfigured, isFalse);
    expect(prefs.enabled, isFalse);
    expect(prefs.lastPushedAt, 0);
  });

  test('migra la key en texto plano de SharedPreferences al almacén seguro y la borra de allí', () async {
    SharedPreferences.setMockInitialValues({'meta_sync_server_url': 'https://x.com', 'meta_sync_api_key': 'vieja-clave'});
    final raw = await SharedPreferences.getInstance();
    final store = MemorySecretStore();
    final prefs = MetaSyncPrefs(raw, store);

    await prefs.load();

    expect(prefs.apiKey, 'vieja-clave');
    expect(await store.read('meta_sync_api_key'), 'vieja-clave');
    expect(raw.getString('meta_sync_api_key'), isNull);
  });

  test('guardar la key no la deja en SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final raw = await SharedPreferences.getInstance();
    final prefs = MetaSyncPrefs(raw, MemorySecretStore());

    await prefs.setCredentials(serverUrl: 'https://x.com', apiKey: 'secreta');

    expect(raw.getString('meta_sync_api_key'), isNull);
    expect(prefs.apiKey, 'secreta');
  });
}
