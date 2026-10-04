import 'date_range.dart';

/// Configuración de una tarjeta de crédito: límite y días de corte y de pago.
/// Se edita en la app (Ajustes > Tarjetas de crédito) y se sincroniza con el servidor,
/// de donde la lee también el puente de correo para sus recordatorios y alertas.
class CardConfig {
  const CardConfig({required this.accountId, this.limitMinor, this.cutDay, this.dueDay});

  final String accountId;

  /// Límite en unidades menores (centavos); `null` = sin definir.
  final int? limitMinor;

  /// Día del mes (1–31) en que cierra el ciclo de facturación; `null` = usar el mes calendario.
  final int? cutDay;

  /// Día del mes (1–31) límite de pago; `null` = sin definir.
  final int? dueDay;

  Map<String, dynamic> toJson() => {'accountId': accountId, 'limitMinor': limitMinor, 'cutDay': cutDay, 'dueDay': dueDay};

  /// Tolerante: ignora valores fuera de rango en vez de fallar (datos de otro cliente o versión).
  static CardConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['accountId'];
    if (id is! String || id.isEmpty) return null;
    int? day(Object? v) => v is int && v >= 1 && v <= 31 ? v : null;
    final limit = json['limitMinor'];
    return CardConfig(accountId: id, limitMinor: limit is int && limit >= 0 ? limit : null, cutDay: day(json['cutDay']), dueDay: day(json['dueDay']));
  }
}

/// Todas las tarjetas + la hora de la última edición (gana la más reciente al sincronizar).
/// `extra` conserva claves que esta versión de la app no conoce, para no borrarlas al guardar.
class CardSettings {
  const CardSettings({this.cards = const {}, this.updatedAt = 0, this.extra = const {}});

  final Map<String, CardConfig> cards;
  final int updatedAt;
  final Map<String, dynamic> extra;

  CardConfig? forAccount(String accountId) => cards[accountId];

  CardSettings withCard(CardConfig card, int now) => CardSettings(cards: {...cards, card.accountId: card}, updatedAt: now, extra: extra);

  /// Lo que se envía a `PUT /v1/config`.
  Map<String, dynamic> toServerConfig() => {...extra, 'cards': [for (final c in cards.values) c.toJson()]};

  factory CardSettings.fromServerConfig(Map<String, dynamic> config, int updatedAt) {
    final cards = <String, CardConfig>{};
    for (final raw in (config['cards'] as List? ?? const [])) {
      final card = CardConfig.fromJson(raw);
      if (card != null) cards[card.accountId] = card;
    }
    return CardSettings(cards: cards, updatedAt: updatedAt, extra: {...config}..remove('cards'));
  }
}

DateTime _clip(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

/// Ciclo de facturación que contiene [now]. Con día de corte, va del día siguiente al corte anterior
/// hasta el corte (inclusive; el día del corte todavía es del ciclo que cierra). Sin él, el mes calendario.
/// Un corte "31" cae en el último día de los meses más cortos.
DateRange cardCycleRange(DateTime now, int? cutDay) {
  final today = DateTime(now.year, now.month, now.day);
  if (cutDay == null) return DateRange(DateTime(today.year, today.month), DateTime(today.year, today.month + 1));
  final thisCut = _clip(today.year, today.month, cutDay);
  if (!today.isAfter(thisCut)) {
    final prevCut = _clip(today.year, today.month - 1, cutDay);
    return DateRange.days(DateTime(prevCut.year, prevCut.month, prevCut.day + 1), thisCut);
  }
  final nextCut = _clip(today.year, today.month + 1, cutDay);
  return DateRange.days(DateTime(thisCut.year, thisCut.month, thisCut.day + 1), nextCut);
}

/// Próxima fecha límite de pago (hoy cuenta); `null` si no hay día de pago.
DateTime? nextDueDate(DateTime now, int? dueDay) {
  if (dueDay == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final thisDue = _clip(today.year, today.month, dueDay);
  return today.isAfter(thisDue) ? _clip(today.year, today.month + 1, dueDay) : thisDue;
}
