"""Gasto del mes vs. presupuestos, y textos de reportes. Todo se calcula con el espejo del servidor."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

APPROACHING, REACHED = 0.8, 1.0


def _live(rows):
    return [r for r in rows if not r.get("deletedAt")]


def _ms(dt: datetime) -> int:
    return int(dt.timestamp() * 1000)


def month_start(now: datetime) -> datetime:
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def money(minor: int, sym: str) -> str:
    return f"{sym}{minor / 100:,.2f}"


def progress(snapshot: dict, now: datetime):
    """[(titulo, gastado_o_neto_minor, límite_minor, kind, budget_id)] del mes en curso."""
    start, end = _ms(month_start(now)), _ms(now) + 1
    txs = [t for t in _live(snapshot["transactions"]) if start <= t["occurredAt"] < end]
    cats = {c["id"]: c["name"] for c in snapshot["categories"]}
    spent_by_cat: dict = {}
    income = expense = 0
    for t in txs:
        if t["type"] == "expense":
            expense += t["amountMinor"]
            spent_by_cat[t["categoryId"]] = spent_by_cat.get(t["categoryId"], 0) + t["amountMinor"]
        else:
            income += t["amountMinor"]
    out = []
    for b in _live(snapshot["budgets"]):
        if b["kind"] == "category":
            out.append((cats.get(b["categoryId"], "Categoría"), spent_by_cat.get(b["categoryId"], 0), b["amountMinor"], "category", b["id"]))
        elif b["kind"] == "overallExpense":
            out.append(("Gasto total del mes", expense, b["amountMinor"], "overallExpense", b["id"]))
        elif b["kind"] == "savings":
            out.append(("Meta de ahorro", income - expense, b["amountMinor"], "savings", b["id"]))
    return out


def new_alerts(snapshot: dict, now: datetime, sym: str, already) -> list:
    """Avisos al cruzar 80% y 100%. `already(key)` evita repetir el mismo aviso en el mes."""
    msgs = []
    for title, current, limit, kind, bid in progress(snapshot, now):
        ratio = current / limit if limit else 0
        for level, name in ((REACHED, "reached"), (APPROACHING, "approaching")):
            if ratio >= level:
                key = f"alert:{now:%Y-%m}:{bid}:{name}"
                if not already(key):
                    msgs.append((key, _alert_text(title, current, limit, kind, level, sym)))
                break  # sólo el nivel más alto cruzado
    return msgs


def _alert_text(title, current, limit, kind, level, sym) -> str:
    pct = f"{current / limit:.0%}"
    if kind == "savings":
        head = "🎯 ¡Meta de ahorro alcanzada!" if level == REACHED else f"🐷 Vas al {pct} de tu meta de ahorro"
    elif level == REACHED:
        head = f"🚨 Te pasaste del presupuesto: {title}"
    else:
        head = f"⚠️ Cuidado, vas al {pct} del presupuesto: {title}"
    return f"{head}\n{money(current, sym)} de {money(limit, sym)}"


def report(snapshot: dict, now: datetime, sym: str, days: int, label: str) -> str:
    since = _ms((now - timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)) if days > 1 else _ms(now.replace(hour=0, minute=0, second=0, microsecond=0))
    cats = {c["id"]: c["name"] for c in snapshot["categories"]}
    txs = [t for t in _live(snapshot["transactions"]) if t["occurredAt"] >= since and t["type"] == "expense"]
    total = sum(t["amountMinor"] for t in txs)
    lines = [f"📊 Reporte {label} — {now:%d/%m/%Y}", f"Gastado: {money(total, sym)} en {len(txs)} movimientos"]
    by_cat: dict = {}
    for t in txs:
        by_cat[cats.get(t["categoryId"], "?")] = by_cat.get(cats.get(t["categoryId"], "?"), 0) + t["amountMinor"]
    for name, amt in sorted(by_cat.items(), key=lambda x: -x[1])[:6]:
        lines.append(f"  • {name}: {money(amt, sym)}")
    top = sorted(txs, key=lambda t: -t["amountMinor"])[:3]
    if top:
        lines.append("Mayores gastos:")
        lines += [f"  • {money(t['amountMinor'], sym)} — {t.get('note') or cats.get(t['categoryId'], '?')}" for t in top]
    prog = progress(snapshot, now)
    if prog:
        lines.append("Presupuestos del mes:")
        for title, cur, lim, kind, _ in prog:
            lines.append(f"  • {title}: {money(cur, sym)} / {money(lim, sym)} ({cur / lim:.0%})")
    return "\n".join(lines)
