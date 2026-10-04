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


def report(snapshot: dict, now: datetime, sym: str, days: int, label: str, card_lines: list | None = None, extra_lines: list | None = None) -> str:
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
    if card_lines:
        lines.append("Tarjetas (consumo del ciclo / límite):")
        lines += card_lines
    prog = progress(snapshot, now)
    if prog:
        lines.append("Presupuestos del mes:")
        for title, cur, lim, kind, _ in prog:
            lines.append(f"  • {title}: {money(cur, sym)} / {money(lim, sym)} ({cur / lim:.0%})")
    lines += extra_lines or []
    return "\n".join(lines)


PERIODS = ("today", "week", "month", "all")


def summary_text(snapshot: dict, now: datetime, sym: str, period: str = "month", category: str | None = None, account: str | None = None) -> str:
    """Respuesta corta a '¿cuánto llevo...?'. Filtra por periodo, categoría y/o cuenta (por nombre, sin importar mayúsculas)."""
    start = {"today": now.replace(hour=0, minute=0, second=0, microsecond=0),
             "week": (now - timedelta(days=6)).replace(hour=0, minute=0, second=0, microsecond=0),
             "month": month_start(now), "all": None}[period]
    lo = _ms(start) if start else 0
    cats = {c["id"]: c["name"] for c in snapshot["categories"]}
    accs = {a["id"]: a["name"] for a in snapshot["accounts"]}
    txs = [t for t in _live(snapshot["transactions"]) if t["occurredAt"] >= lo
           and (not category or cats.get(t["categoryId"], "").lower() == category.lower())
           and (not account or accs.get(t["accountId"], "").lower() == account.lower())]
    expense = sum(t["amountMinor"] for t in txs if t["type"] == "expense")
    income = sum(t["amountMinor"] for t in txs if t["type"] == "income")
    label = {"today": "hoy", "week": "últimos 7 días", "month": "este mes", "all": "en total"}[period]
    scope = " · ".join(x for x in (category, account) if x)
    out = [f"{label.capitalize()}{' — ' + scope if scope else ''}: gastos {money(expense, sym)}, ingresos {money(income, sym)} ({len(txs)} movimientos)"]
    by_cat: dict = {}
    for t in txs:
        if t["type"] == "expense":
            by_cat[cats.get(t["categoryId"], "?")] = by_cat.get(cats.get(t["categoryId"], "?"), 0) + t["amountMinor"]
    out += [f"  • {name}: {money(v, sym)}" for name, v in sorted(by_cat.items(), key=lambda x: -x[1])[:8]]
    return "\n".join(out)


def account_balance(snapshot: dict, account_id: str) -> int:
    return sum(t["amountMinor"] * (1 if t["type"] == "income" else -1) for t in _live(snapshot["transactions"]) if t["accountId"] == account_id)


def goals_lines(snapshot: dict, goals: list, sym: str) -> list:
    ids = {a["name"].lower(): a["id"] for a in _live(snapshot["accounts"])}
    out = []
    for g in goals:
        aid = ids.get(g.get("account", "").lower())
        target = round(float(g.get("target", 0)) * 100)
        if aid and target:
            bal = account_balance(snapshot, aid)
            out.append(f"  • {g['name']}: {money(bal, sym)} / {money(target, sym)} ({max(bal, 0) / target:.0%})")
    return (["Metas de ahorro:"] + out) if out else []


def monthly_workbook(snapshot: dict, first: datetime, sym: str, card_rows: list, subs: list) -> tuple:
    """(hojas, resumen) del mes que empieza en `first`. Hojas: Resumen, Movimientos, Suscripciones."""
    nxt = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    lo, hi = _ms(first), _ms(nxt)
    cats = {c["id"]: c["name"] for c in snapshot["categories"]}
    accs = {a["id"]: a["name"] for a in snapshot["accounts"]}
    txs = sorted((t for t in _live(snapshot["transactions"]) if lo <= t["occurredAt"] < hi), key=lambda t: t["occurredAt"])
    expenses = [t for t in txs if t["type"] == "expense"]
    total_exp = sum(t["amountMinor"] for t in expenses)
    total_inc = sum(t["amountMinor"] for t in txs if t["type"] == "income")
    by_cat: dict = {}
    by_acc: dict = {}
    for t in expenses:
        by_cat[cats.get(t["categoryId"], "?")] = by_cat.get(cats.get(t["categoryId"], "?"), 0) + t["amountMinor"]
        by_acc[accs.get(t["accountId"], "?")] = by_acc.get(accs.get(t["accountId"], "?"), 0) + t["amountMinor"]
    resumen = [["Concepto", "Monto"], ["Gastos del mes", total_exp / 100], ["Ingresos del mes", total_inc / 100], ["Neto", (total_inc - total_exp) / 100], [], ["Gasto por categoría", ""]]
    resumen += [[k, v / 100] for k, v in sorted(by_cat.items(), key=lambda x: -x[1])] + [[], ["Gasto por cuenta", ""]] + [[k, v / 100] for k, v in sorted(by_acc.items(), key=lambda x: -x[1])]
    movs = [["Fecha", "Cuenta", "Tipo", "Categoría", "Detalle", "Monto"]]
    movs += [[datetime.fromtimestamp(t["occurredAt"] / 1000, first.tzinfo).strftime("%Y-%m-%d %H:%M"), accs.get(t["accountId"], "?"),
              "Gasto" if t["type"] == "expense" else "Ingreso", cats.get(t["categoryId"], "?"), t.get("note") or "", t["amountMinor"] / 100] for t in txs]
    subsheet = [["Suscripción", "Monto", "Cada (días)", "Último cobro", "Próximo cobro"]]
    subsheet += [[x["label"], x["amount"] / 100, x["every_days"], datetime.fromtimestamp(x["last"] / 1000, first.tzinfo).strftime("%Y-%m-%d"),
                  datetime.fromtimestamp(x["next"] / 1000, first.tzinfo).strftime("%Y-%m-%d")] for x in subs]
    text = [f"📊 Reporte de {first:%m/%Y}: gastos {money(total_exp, sym)}, ingresos {money(total_inc, sym)}, neto {money(total_inc - total_exp, sym)}"]
    text += [f"  • {k}: {money(v, sym)}" for k, v in sorted(by_cat.items(), key=lambda x: -x[1])[:6]]
    return [("Resumen", resumen), ("Movimientos", movs), ("Suscripciones", subsheet)], "\n".join(text)
