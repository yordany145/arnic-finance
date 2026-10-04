"""Análisis sobre el historial: consumos inusuales, categorías aprendidas y suscripciones. Funciones puras."""
import calendar
from datetime import datetime, timezone
from statistics import median

from .parser import categorize, foreign_country, merchant_key

BRIDGE_MARK = "(tarjeta ••"  # las notas que crea el puente llevan esto; las manuales no

DEFAULT_UNUSUAL = {"large_min": 5000, "large_factor": 3.0, "new_merchant_min": 3000, "min_history": 5}


def _history(snapshot: dict) -> list:
    return [t for t in snapshot["transactions"] if t["type"] == "expense" and not t.get("deletedAt") and BRIDGE_MARK in (t.get("note") or "")]


def unusual_reasons(snapshot: dict, merchant: str, amount_minor: int, settings: dict | None = None) -> list:
    """Motivos por los que un consumo merece atención (lista vacía = normal). Se evalúa ANTES de registrarlo."""
    cfg = {**DEFAULT_UNUSUAL, **(settings or {})}
    reasons = []
    country = foreign_country(merchant)
    if country:
        reasons.append(f"comercio en el extranjero ({country})")
    history = _history(snapshot)
    if len(history) >= cfg["min_history"]:
        typical = median(t["amountMinor"] for t in history[-60:])
        if amount_minor >= max(cfg["large_min"] * 100, cfg["large_factor"] * typical):
            reasons.append(f"monto alto: {amount_minor / typical:.1f}× tu consumo típico")
        seen = {merchant_key(t["note"]) for t in history}
        if merchant_key(merchant) not in seen and amount_minor >= cfg["new_merchant_min"] * 100:
            reasons.append("comercio nuevo")
    return reasons


def learn_categories(snapshot: dict, rules: dict, fallback: str) -> dict:
    """Comercios cuya categoría el usuario cambió a mano en la app → {clave de comercio: categoría}.
    Se recorre en orden de edición: gana el último cambio. Si volvió a la categoría automática, el valor es `None` (olvidar)."""
    names = {c["id"]: c["name"] for c in snapshot["categories"]}
    learned: dict = {}
    for t in sorted(_history(snapshot), key=lambda t: t["updatedAt"]):
        merchant = t["note"].split(" (tarjeta")[0]
        actual = names.get(t["categoryId"])
        if actual is None:
            continue
        key = merchant_key(merchant)
        if actual != categorize(merchant, rules, fallback):
            learned[key] = actual
        else:
            learned[key] = None
    return learned


def _same_day_next_month(ms: int, tz) -> int:
    d = datetime.fromtimestamp(ms / 1000, tz)
    year, month = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return int(d.replace(year=year, month=month, day=min(d.day, calendar.monthrange(year, month)[1])).timestamp() * 1000)


def detect_subscriptions(events: list, tz=timezone.utc, now_ms: int | None = None) -> list:
    """events: [(clave, etiqueta, monto_minor, cuando_ms)].

    Un cobro mensual es una cadena de cargos que termina en el último de ese comercio: cada uno ~30 días (25–35) después
    del anterior y con un monto parecido (±20 %). Las compras sueltas que no encajan en la cadena —otro monto, otra fecha—
    se ignoran en vez de estropear la detección. El próximo cobro se espera el mismo día del mes siguiente (zona `tz`).
    Con `now_ms`, se descartan las que llevan más de una semana de retraso (ya no se cobran)."""
    day = 86_400_000
    groups: dict = {}
    for key, label, amount, when in events:
        groups.setdefault(key, []).append((when, amount, label))
    found = []
    for items in groups.values():
        items.sort()
        head = items[-1]
        chain = [head]
        while True:
            candidates = [it for it in items if 25 <= (head[0] - it[0]) / day <= 35 and max(it[1], head[1]) <= 1.2 * min(it[1], head[1])]
            if not candidates:
                break
            head = min(candidates, key=lambda it: abs((head[0] - it[0]) / day - 30))
            chain.append(head)
        if len(chain) < 2:
            continue
        last_when, last_amount, label = chain[0]
        next_ms = _same_day_next_month(last_when, tz)
        if now_ms is not None and next_ms < now_ms - 7 * day:
            continue
        gaps = [(a[0] - b[0]) / day for a, b in zip(chain, chain[1:])]
        found.append({"label": label, "amount": last_amount, "every_days": round(median(gaps)), "last": last_when, "next": next_ms, "charges": len(chain)})
    return sorted(found, key=lambda s: s["next"])


def subscription_events(snapshot: dict) -> list:
    return [(merchant_key(t["note"]), t["note"].split(" (tarjeta")[0], t["amountMinor"], t["occurredAt"]) for t in _history(snapshot)]
