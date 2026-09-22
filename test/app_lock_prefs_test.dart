import 'package:arnic_finance/data/app_lock_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('desactivado por defecto, y persiste al activarlo', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppLockPrefs(await SharedPreferences.getInstance());
    expect(prefs.enabled, isFalse);

    await prefs.setEnabled(true);
    expect(prefs.enabled, isTrue);

    await prefs.setEnabled(false);
    expect(prefs.enabled, isFalse);
  });
}
