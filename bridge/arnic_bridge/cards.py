"""Tarjetas de crédito: ciclo de facturación, límite, fecha de pago y avisos.

Los límites y los días de corte y de pago los edita el usuario en la app; la app los guarda en el servidor
(`GET /v1/config`) y de ahí los lee el puente. `config.local.json` solo aporta lo que la app no sabe:
qué banco usa qué cuenta y los últimos 4 dígitos. Si el servidor no tiene un dato, se usa el de la config local.

El consumo del ciclo NO descuenta pagos (el usuario pidió ignorar pagos): mide cuánto se ha consumido
en el ciclo frente al límite, no la deuda total.
"""
import calendar
from datetime import date, datetime, timedelta

from .budgets import _live, money


def _clip(year: int, month: int, day: int) -> date:
    return date(year, month, min(day, calendar.monthrange(year, month)[1]))


def _next_month_first(d: date) -> date:
    return (d.replace(day=28) + timedelta(days=4)).replace(day=1)


def cycle_bounds(today: date, cut_day: int | None) -> tuple:
    """(inicio, fin) inclusivos del ciclo que contiene `today`. Sin día de corte, el mes calendario."""
    if not cut_day:
        return today.replace(day=1), _next_month_first(today) - timedelta(days=1)
    this_cut = _clip(today.year, today.month, cut_day)
    if today <= this_cut:
        prev = this_cut.replace(day=1) - timedelta(days=1)
        return _clip(prev.year, prev.month, cut_day) + timedelta(days=1), this_cut
    nxt = _next_month_first(this_cut)
    return this_cut + timedelta(days=1), _clip(nxt.year, nxt.month, cut_day)


def next_due(today: date, due_day: int | None) -> date | None:
    if not due_day:
        return None
    this_due = _clip(today.year, today.month, due_day)
    if today <= this_due:
        return this_due
    nxt = _next_month_first(this_due)
    return _clip(nxt.year, nxt.month, due_day)


def effective_cards(local: dict, snapshot: dict, server_config: dict | None) -> dict:
    """banco → {account, account_id, limit_minor, cut_day, due_day, last4}, con lo del servidor por encima de lo local."""
    ids = {a["name"]: a["id"] for a in _live(snapshot["accounts"])}
    from_server = {c["accountId"]: c for c in (server_config or {}).get("cards", [])}
    out = {}
    for bank, c in local.items():
        account_id = ids.get(c.get("account", ""))
        s = from_server.get(account_id, {})
        out[bank] = {
            "account": c.get("account", bank),
            "account_id": account_id,
            "limit_minor": s["limitMinor"] if s.get("limitMinor") is not None else round(float(c.get("limit", 0)) * 100),
            "cut_day": s["cutDay"] if s.get("cutDay") is not None else c.get("cut_day"),
            "due_day": s["dueDay"] if s.get("dueDay") is not None else c.get("due_day"),
            "last4": c.get("last4", []),
        }
    return out


def usage(snapshot: dict, now: datetime, cards: dict) -> list:
    """Una fila por tarjeta con lo consumido en su ciclo actual."""
    rows = []
    tz = now.tzinfo
    for bank, c in cards.items():
        start, end = cycle_bounds(now.date(), c["cut_day"])
        lo = int(datetime(start.year, start.month, start.day, tzinfo=tz).timestamp() * 1000)
        hi_day = end + timedelta(days=1)
        hi = int(datetime(hi_day.year, hi_day.month, hi_day.day, tzinfo=tz).timestamp() * 1000)
        spent = sum(t["amountMinor"] for t in _live(snapshot["transactions"])
                    if t["type"] == "expense" and t["accountId"] == c["account_id"] and lo <= t["occurredAt"] < hi)
        rows.append({"bank": bank, "account": c["account"], "spent": spent, "limit": c["limit_minor"], "available": max(c["limit_minor"] - spent, 0),
                     "start": start, "end": end, "cut_day": c["cut_day"], "due": next_due(now.date(), c["due_day"])})
    return rows


def alerts(rows: list, sym: str, already) -> list:
    """Aviso al 80% y al 100% del límite dentro de cada ciclo (una vez por nivel y ciclo)."""
    msgs = []
    for r in rows:
        if not r["limit"]:
            continue
        ratio = r["spent"] / r["limit"]
        for level, name in ((1.0, "reached"), (0.8, "approaching")):
            if ratio >= level:
                key = f"cardalert:{r['start']:%Y%m%d}:{r['bank']}:{name}"
                if not already(key):
                    head = f"🚨 Llegaste al límite de {r['account']}" if level == 1.0 else f"⚠️ {r['account']}: vas al {ratio:.0%} de su límite"
                    msgs.append((key, f"{head}\nConsumo del ciclo: {money(r['spent'], sym)} de {money(r['limit'], sym)}\n"
                                      f"Disponible: {money(r['available'], sym)} · el ciclo cierra el {r['end']:%d/%m}"))
                break
    return msgs


def due_reminders(rows: list, already, today: date) -> list:
    """Recordatorio del pago 3 días antes, el día anterior y el mismo día."""
    msgs = []
    for r in rows:
        if not r["due"]:
            continue
        left = (r["due"] - today).days
        if left in (3, 1, 0):
            key = f"due:{r['due'].isoformat()}:{r['bank']}:{left}"
            if not already(key):
                when = "hoy" if left == 0 else "mañana" if left == 1 else f"en {left} días"
                msgs.append((key, f"💳 El pago de {r['account']} vence {when} ({r['due']:%d/%m})."))
    return msgs


def lines(rows: list, sym: str) -> list:
    out = []
    for r in rows:
        text = f"  • {r['account']}: {money(r['spent'], sym)}"
        if r["limit"]:
            text += f" / {money(r['limit'], sym)} ({r['spent'] / r['limit']:.0%}), disponible {money(r['available'], sym)}"
        text += f" · ciclo {r['start']:%d/%m}–{r['end']:%d/%m}"
        if r["due"]:
            text += f" · pago {r['due']:%d/%m}"
        out.append(text)
    return out
