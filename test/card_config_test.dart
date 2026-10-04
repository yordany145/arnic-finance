import 'package:arnic_finance/data/card_settings_store.dart';
import 'package:arnic_finance/domain/card_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('cardCycleRange (mismas reglas que el puente de correo)', () {
    String show(DateTime now, int? cut) {
      final r = cardCycleRange(now, cut);
      return '${r.start.toIso8601String().substring(0, 10)}..${r.lastDay.toIso8601String().substring(0, 10)}';
    }

    test('con día de corte', () {
      expect(show(DateTime(2026, 10, 3), 15), '2026-09-16..2026-10-15');
      expect(show(DateTime(2026, 10, 15), 15), '2026-09-16..2026-10-15'); // el día del corte aún es del ciclo que cierra
      expect(show(DateTime(2026, 10, 16), 15), '2026-10-16..2026-11-15');
      expect(show(DateTime(2026, 12, 20), 15), '2026-12-16..2027-01-15'); // cruza de año
      expect(show(DateTime(2026, 1, 5), 15), '2025-12-16..2026-01-15');
    });

    test('corte 31 cae en el último día de los meses cortos', () {
      expect(show(DateTime(2026, 3, 5), 31), '2026-03-01..2026-03-31'); // el corte de febrero fue el 28
      expect(show(DateTime(2026, 2, 10), 31), '2026-02-01..2026-02-28');
    });

    test('sin día de corte: mes calendario', () {
      expect(show(DateTime(2026, 10, 3), null), '2026-10-01..2026-10-31');
    });

    test('el rango incluye todo el último día (hasta las 23:59)', () {
      final r = cardCycleRange(DateTime(2026, 10, 3), 15);
      expect(r.contains(DateTime(2026, 10, 15, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 10, 16)), isFalse);
      expect(r.contains(DateTime(2026, 9, 16)), isTrue);
      expect(r.contains(DateTime(2026, 9, 15, 23, 59)), isFalse);
    });
  });

  test('nextDueDate', () {
    expect(nextDueDate(DateTime(2026, 10, 3), 5), DateTime(2026, 10, 5));
    expect(nextDueDate(DateTime(2026, 10, 5), 5), DateTime(2026, 10, 5)); // hoy cuenta
    expect(nextDueDate(DateTime(2026, 10, 6), 5), DateTime(2026, 11, 5));
    expect(nextDueDate(DateTime(2026, 1, 31), 30), DateTime(2026, 2, 28));
    expect(nextDueDate(DateTime(2026, 12, 20), 5), DateTime(2027, 1, 5));
    expect(nextDueDate(DateTime(2026, 10, 3), null), isNull);
  });

  group('CardConfig / CardSettings', () {
    test('fromJson ignora días y límites inválidos en vez de fallar', () {
      final c = CardConfig.fromJson({'accountId': 'a', 'limitMinor': -5, 'cutDay': 40, 'dueDay': 0});
      expect(c?.limitMinor, isNull);
      expect(c?.cutDay, isNull);
      expect(c?.dueDay, isNull);
      expect(CardConfig.fromJson({'limitMinor': 5}), isNull); // sin accountId
      expect(CardConfig.fromJson('basura'), isNull);
    });

    test('ida y vuelta con el servidor conserva las claves desconocidas', () {
      final settings = CardSettings.fromServerConfig({
        'cards': [{'accountId': 'a', 'limitMinor': 1500000, 'cutDay': 15, 'dueDay': 5}],
        'goals': [{'name': 'Fondo'}],
      }, 100);
      expect(settings.forAccount('a')?.limitMinor, 1500000);
      final saved = settings.withCard(const CardConfig(accountId: 'b', limitMinor: 3000000), 200);
      expect(saved.updatedAt, 200);
      final json = saved.toServerConfig();
      expect((json['cards'] as List).length, 2);
      expect(json['goals'], [{'name': 'Fondo'}]);
    });
  });

  group('CardSettingsStore', () {
    test('guarda y lee', () async {
      SharedPreferences.setMockInitialValues({});
      final store = CardSettingsStore(await SharedPreferences.getInstance());
      expect(store.read().cards, isEmpty);
      await store.write(const CardSettings().withCard(const CardConfig(accountId: 'a', limitMinor: 100, cutDay: 3, dueDay: 4), 77));
      final back = store.read();
      expect(back.updatedAt, 77);
      expect(back.forAccount('a')?.dueDay, 4);
    });

    test('un dato local dañado no rompe la app: se parte de cero', () async {
      SharedPreferences.setMockInitialValues({'card_settings_v1': '{no es json'});
      final store = CardSettingsStore(await SharedPreferences.getInstance());
      expect(store.read().cards, isEmpty);
    });
  });
}
