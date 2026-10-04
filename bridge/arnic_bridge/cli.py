import argparse
import sys
import tempfile
import time
import unicodedata
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from . import budgets, cards as cardlib, config, export, insights, ledger, mail_source
from .client import Arnic, ApiError
from .parser import NotAPurchase, categorize, merchant_key, parse_email, parse_qik_deposit
from .state import State
from .telegram import Telegram

QIK_SENDER = "@mail.qik.com.do"
TWELVE_HOURS_MS = 12 * 60 * 60 * 1000


def _tz(cfg) -> ZoneInfo:
    return ZoneInfo(getattr(cfg, "timezone", "America/Santo_Domingo"))


def _plain(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn").lower()


def build_context(cfg, arnic, state, snapshot=None) -> dict:
    """Lo que el procesamiento necesita además del correo: tarjetas con su configuración vigente y categorías aprendidas."""
    snapshot = snapshot if snapshot is not None else arnic.snapshot()
    effective = cardlib.effective_cards(cfg.cards, snapshot, arnic.get_config())
    for key, category in insights.learn_categories(snapshot, cfg.category_rules, cfg.fallback_category).items():
        if category is None:
            state.forget(key)
        else:
            state.learn(key, category)
    names = {c["name"] for c in snapshot["categories"] if c["type"] == "expense" and not c.get("deletedAt")}
    return {"cards": effective, "learned": state.learned(), "expense_categories": names, "snapshot": snapshot}


def _is_salary(income, salary: dict) -> bool:
    if not salary.get("amount"):
        return False
    target = round(float(salary["amount"]) * 100)
    tolerance = float(salary.get("tolerance_pct", 10)) / 100
    origins = [_plain(o) for o in salary.get("origin_contains", ["reserva"])]
    return abs(income.amount_minor - target) <= target * tolerance and any(o in _plain(income.origin) for o in origins)


def _process_qik(mail, cfg, arnic, tg, state, dry_run, snapshot, key) -> str:
    """Depósito recibido en Qik. La descripción que el usuario escribe no llega en el aviso: el sueldo se reconoce
    por el banco de origen y el monto (config `salary`). Cualquier otro depósito se ignora, como pidió el usuario."""
    try:
        income = parse_qik_deposit(mail.subject, mail.body)
    except NotAPurchase:
        if not dry_run:
            state.add(key)  # transferencias enviadas, promociones, encuestas…
        return "omitido"
    salary = getattr(cfg, "salary", None) or {}
    when = income.when_ms or mail.date_ms
    if not _is_salary(income, salary) or (snapshot is not None and ledger.is_duplicate(snapshot, income.amount_minor, when, TWELVE_HOURS_MS, "income")):
        if not dry_run:
            state.add(key)
        return "omitido"
    account, category = salary.get("account", "Qik ahorros"), salary.get("category", "Salario")
    note = f"Sueldo — depósito desde {income.origin}"
    shown = budgets.money(income.amount_minor, cfg.currency_symbol)
    if dry_run:
        print(f"[dry-run] INGRESO {shown} | {category} | {note} | {account}")
        return "registrado"
    try:
        arnic.add_income(income.amount_minor, category, note, when, account)
    except ApiError as e:
        tg.send(f"⚠️ No pude registrar el sueldo de {shown}: {e}. Lo reintentaré en la próxima corrida.")
        return "error"
    if snapshot is not None:
        snapshot["transactions"].append({"type": "income", "amountMinor": income.amount_minor, "occurredAt": when, "deletedAt": None})
    tg.send(f"💰 Sueldo recibido: {shown} → {account}\n(depósito desde {income.origin})")
    state.add(key)
    return "registrado"


def process_mail(mail, cfg, arnic, tg, state, dry_run=False, snapshot=None, quiet_log=None, ctx=None) -> str:
    """Devuelve 'registrado' | 'omitido' | 'error'. Marca el correo como visto para no repetirlo."""
    key = f"mail:{mail.message_id}"
    if state.has(key):
        return "omitido"
    if mail.sender.endswith(QIK_SENDER):
        return _process_qik(mail, cfg, arnic, tg, state, dry_run, snapshot, key)
    try:
        purchases = parse_email(mail.sender, mail.subject, mail.body)
    except NotAPurchase:
        state.add(key)  # depósitos, transferencias, pagos, publicidad: no son consumos de tarjeta
        return "omitido"
    ctx = ctx or {}
    result, failed = "omitido", False
    for p in purchases:
        amount = p.amount_minor
        if p.currency == "USD":
            if not cfg.usd_to_local:
                if quiet_log is not None:
                    quiet_log["usd"].append(f"US${amount / 100:,.2f} · {p.merchant}")
                elif not dry_run:
                    tg.send(f"💳 Consumo en USD de ${amount / 100:,.2f} en {p.merchant}. No lo registré: falta `usd_to_local` en la config.")
                failed = quiet_log is None
                continue
            amount = round(amount * cfg.usd_to_local)
        when = p.when_ms or mail.date_ms
        if snapshot is not None and ledger.is_duplicate(snapshot, amount, when):
            continue
        card = cfg.cards.get(p.bank, {})
        if card.get("last4") and p.card_last4 not in card["last4"]:
            continue  # otra tarjeta (p. ej. de débito): solo se registran las tarjetas de crédito configuradas
        learned = ctx.get("learned", {}).get(merchant_key(p.merchant))
        valid = ctx.get("expense_categories")
        category = learned if learned and (valid is None or learned in valid) else categorize(p.merchant, cfg.category_rules, cfg.fallback_category)
        note = p.merchant + (f" (tarjeta ••{p.card_last4})" if p.card_last4 else "")
        account = card.get("account") or cfg.card_account
        if dry_run:
            print(f"[dry-run] {budgets.money(amount, cfg.currency_symbol)} | {category} | {note} | {account or 'cuenta predeterminada'}")
            result = "registrado"
            continue
        reasons = insights.unusual_reasons(snapshot, p.merchant, amount, getattr(cfg, "unusual", None)) if snapshot is not None and quiet_log is None else []
        try:
            arnic.add_expense(amount, category, note, when, account)
        except ApiError as e:
            tg.send(f"⚠️ No pude registrar {budgets.money(amount, cfg.currency_symbol)} en {p.merchant}: {e}. Lo reintentaré en la próxima corrida.")
            failed = True
            continue
        account_id = ctx.get("cards", {}).get(p.bank, {}).get("account_id")
        if snapshot is not None:  # que otra compra igual del mismo correo no se tome por duplicada de ésta
            snapshot["transactions"].append({"type": "expense", "amountMinor": amount, "occurredAt": when, "deletedAt": None, "accountId": account_id, "categoryId": None})
        if quiet_log is not None:
            quiet_log["rows"].append((when, amount, category, account or "—", note))
        else:
            text = f"💳 {budgets.money(amount, cfg.currency_symbol)} · {category}\n{note}" + (f"\n{account}" if account else "")
            row = next((r for r in cardlib.usage(snapshot, datetime.now(_tz(cfg)), ctx["cards"]) if r["bank"] == p.bank), None) if snapshot is not None and ctx.get("cards") else None
            if row and row["limit"]:
                text += f"\nDisponible: {budgets.money(row['available'], cfg.currency_symbol)} de {budgets.money(row['limit'], cfg.currency_symbol)}"
            if reasons:
                text += "\n🔎 Consumo inusual: " + "; ".join(reasons)
            tg.send(text)
        result = "registrado"
    if failed:
        return "error"  # sin marcar: se reintenta (la guarda anti-duplicados evita repetir las que sí entraron)
    if not dry_run:
        state.add(key)
    return result


def _backfill_summary(log, cfg) -> str:
    by_account: dict = {}
    for _, amount, _, account, _ in log["rows"]:
        by_account[account] = by_account.get(account, 0) + amount
    lines = [f"📥 Historial cargado: {len(log['rows'])} consumos"] + [f"  • {a}: {budgets.money(t, cfg.currency_symbol)}" for a, t in sorted(by_account.items())]
    if log["usd"]:
        lines += [f"⚠️ {len(log['usd'])} en USD sin registrar (falta usd_to_local):"] + [f"  • {u}" for u in log["usd"]]
    return "\n".join(lines)


def _print_backfill(log, cfg) -> None:
    tz = _tz(cfg)
    for when, amount, category, account, note in sorted(log["rows"]):
        print(f"{datetime.fromtimestamp(when / 1000, tz):%d/%m %H:%M} | {budgets.money(amount, cfg.currency_symbol):>12} | {category:<15} | {account:<20} | {note}")
    for u in log["usd"]:
        print(f"SIN REGISTRAR (USD): {u}")


def check_alerts(cfg, arnic, tg, state) -> int:
    """Alertas de presupuesto y de límite de tarjeta, con datos frescos del servidor."""
    now = datetime.now(_tz(cfg))
    snap = arnic.snapshot()
    rows = cardlib.usage(snap, now, cardlib.effective_cards(cfg.cards, snap, arnic.get_config()))
    msgs = budgets.new_alerts(snap, now, cfg.currency_symbol, state.has) + cardlib.alerts(rows, cfg.currency_symbol, state.has)
    for key, text in msgs:
        tg.send(text)
        state.add(key)
    return len(msgs)


def _subscriptions(cfg, snapshot, mail_days: int = 0) -> list:
    """Cobros mensuales recurrentes: del historial registrado y, opcionalmente, del correo de los últimos `mail_days` días (solo lectura)."""
    events = list(insights.subscription_events(snapshot))
    if mail_days:
        for m in mail_source.fetch_recent(cfg.imap_host, cfg.imap_user, cfg.imap_password, cfg.imap_folder, cfg.bank_senders, mail_days):
            try:
                for p in parse_email(m.sender, m.subject, m.body):
                    if p.currency == "LOCAL":
                        events.append((merchant_key(p.merchant), p.merchant, p.amount_minor, p.when_ms or m.date_ms))
            except NotAPurchase:
                pass
        events = list({(k, w // 60000): (k, label, a, w) for k, label, a, w in events}.values())
    return insights.detect_subscriptions(events, _tz(cfg))


def _upcoming_subscription_lines(subs: list, now: datetime, sym: str, within_days: int = 3) -> list:
    horizon = int((now + timedelta(days=within_days)).timestamp() * 1000)
    soon = [s for s in subs if int(now.timestamp() * 1000) <= s["next"] <= horizon]
    return (["Próximos cobros recurrentes:"] + [f"  • {s['label']}: {budgets.money(s['amount'], sym)} hacia el {datetime.fromtimestamp(s['next'] / 1000, now.tzinfo):%d/%m}" for s in soon]) if soon else []


def main(argv=None):
    ap = argparse.ArgumentParser(prog="arnic_bridge")
    ap.add_argument("--config")
    sub = ap.add_subparsers(dest="cmd", required=True)
    ing = sub.add_parser("ingest", help="lee el correo del banco, registra gastos y avisa si se cruza un presupuesto")
    ing.add_argument("--dry-run", action="store_true", help="muestra lo que haría sin registrar ni avisar")
    ing.add_argument("--file", help="probar con un .eml guardado en vez de leer el correo")
    ing.add_argument("--since", type=date.fromisoformat, help="cargar historial desde esta fecha (AAAA-MM-DD)")
    ing.add_argument("--until", type=date.fromisoformat, help="hasta esta fecha, inclusive (por defecto, hoy)")
    ing.add_argument("--quiet", action="store_true", help="sin un aviso por compra: manda un solo resumen por Telegram")
    rep = sub.add_parser("report", help="manda un reporte por Telegram")
    rep.add_argument("period", choices=["daily", "weekly", "monthly"])
    rep.add_argument("--month", help="para monthly: AAAA-MM (por defecto, el mes anterior)")
    rep.add_argument("--print", action="store_true", dest="only_print", help="mostrar en vez de enviar por Telegram")
    summ = sub.add_parser("summary", help="responde '¿cuánto llevo?' (por periodo, categoría y/o cuenta)")
    summ.add_argument("--period", choices=budgets.PERIODS, default="month")
    summ.add_argument("--category")
    summ.add_argument("--account")
    sub.add_parser("cards", help="estado de cada tarjeta: ciclo, consumo, límite y fecha de pago")
    subs = sub.add_parser("subscriptions", help="cobros mensuales recurrentes detectados")
    subs.add_argument("--mail-days", type=int, default=0, help="además, buscar en el correo de los últimos N días")
    for name, help_ in (("add-expense", "registra un gasto a mano (p. ej. efectivo)"), ("add-income", "registra un ingreso a mano")):
        m = sub.add_parser(name, help=help_)
        m.add_argument("amount", type=float)
        m.add_argument("category")
        m.add_argument("--note", default="")
        m.add_argument("--account", default="")
    acc = sub.add_parser("add-account", help="crea una cuenta con su saldo inicial (como ingreso)")
    acc.add_argument("name")
    acc.add_argument("--kind", default="savings", choices=sorted(ledger.ICONS))
    acc.add_argument("--balance", type=float, default=0, help="saldo actual en unidades, ej. 37000")
    acc.add_argument("--dry-run", action="store_true")
    dele = sub.add_parser("delete-movements", help="borra movimientos cuya nota contenga el texto")
    dele.add_argument("--note-contains", action="append", required=True)
    dele.add_argument("--dry-run", action="store_true")
    sub.add_parser("check", help="verifica que la configuración y las conexiones funcionan")
    args = ap.parse_args(argv)

    cfg = config.load(args.config)
    arnic, tg, state = Arnic(cfg.server_url, cfg.api_key), Telegram(cfg.telegram_config_path), State(cfg.state_path)
    sym, tz = cfg.currency_symbol, _tz(cfg)

    if args.cmd == "ingest":
        if args.file:
            mails = [mail_source.from_bytes(open(args.file, "rb").read())]
        elif args.since:
            before = (args.until + timedelta(days=1)) if args.until else None
            mails = mail_source.fetch_range(cfg.imap_host, cfg.imap_user, cfg.imap_password, cfg.imap_folder, cfg.bank_senders, args.since, before)
        else:
            mails = mail_source.fetch_recent(cfg.imap_host, cfg.imap_user, cfg.imap_password, cfg.imap_folder, cfg.bank_senders, cfg.lookback_days)
        counts = {"registrado": 0, "omitido": 0, "error": 0}
        snapshot = arnic.snapshot()
        ctx = build_context(cfg, arnic, state, snapshot)
        quiet_log = {"rows": [], "usd": []} if args.quiet else None
        for m in mails:
            counts[process_mail(m, cfg, arnic, tg, state, args.dry_run, snapshot, quiet_log, ctx)] += 1
        if quiet_log is not None:
            _print_backfill(quiet_log, cfg)
            if not args.dry_run and (quiet_log["rows"] or quiet_log["usd"]):
                tg.send(_backfill_summary(quiet_log, cfg))
        if counts["registrado"] and not args.dry_run and not args.since:
            check_alerts(cfg, arnic, tg, state)
        print(counts)
        return 1 if counts["error"] else 0

    now = datetime.now(tz)
    if args.cmd == "report":
        snap = arnic.snapshot()
        rows = cardlib.usage(snap, now, cardlib.effective_cards(cfg.cards, snap, arnic.get_config()))
        subs_found = _subscriptions(cfg, snap)
        if args.period == "monthly":
            first = (datetime.strptime(args.month, "%Y-%m").replace(tzinfo=tz) if args.month else (now.replace(day=1) - timedelta(days=1)).replace(day=1, hour=0, minute=0, second=0, microsecond=0))
            sheets, text = budgets.monthly_workbook(snap, first, sym, rows, subs_found)
            path = f"{tempfile.gettempdir()}/arnic-reporte-{first:%Y-%m}.xlsx"
            export.write_xlsx(path, sheets)
            print(text + f"\nArchivo: {path}")
            if not args.only_print:
                tg.send_document(path, text)
            return 0
        extra = budgets.goals_lines(snap, cfg.goals, sym) + _upcoming_subscription_lines(subs_found, now, sym)
        text = budgets.report(snap, now, sym, 1 if args.period == "daily" else 7, "diario" if args.period == "daily" else "semanal", cardlib.lines(rows, sym), extra)
        if args.only_print:
            print(text)
            return 0
        if args.period == "daily":
            for key, reminder in cardlib.due_reminders(rows, state.has, now.date()):
                tg.send(reminder)
                state.add(key)
        tg.send(text)
        return 0
    if args.cmd == "summary":
        print(budgets.summary_text(arnic.snapshot(), now, sym, args.period, args.category, args.account))
        return 0
    if args.cmd == "cards":
        snap = arnic.snapshot()
        rows = cardlib.usage(snap, now, cardlib.effective_cards(cfg.cards, snap, arnic.get_config()))
        print("\n".join(cardlib.lines(rows, sym)) or "No hay tarjetas configuradas.")
        return 0
    if args.cmd == "subscriptions":
        found = _subscriptions(cfg, arnic.snapshot(), args.mail_days)
        for s in found:
            print(f"{s['label']}: {budgets.money(s['amount'], sym)} cada ~{s['every_days']} días · próximo {datetime.fromtimestamp(s['next'] / 1000, tz):%d/%m/%Y}")
        print(f"{len(found)} suscripción(es) detectada(s)")
        return 0
    if args.cmd in ("add-expense", "add-income"):
        add = arnic.add_expense if args.cmd == "add-expense" else arnic.add_income
        r = add(round(args.amount * 100), args.category, args.note, int(time.time() * 1000), args.account)
        print(f"Registrado: {budgets.money(r['amountMinor'], sym)} · {r['category']} · {r['account']}" + (f" · {r['note']}" if r.get("note") else ""))
        return 0
    if args.cmd == "add-account":
        rows, text = ledger.plan_account(arnic.snapshot(), args.name, args.kind, round(args.balance * 100))
        print(("[dry-run] " if args.dry_run else "") + text)
        if not args.dry_run and (rows["accounts"] or rows["transactions"]):
            arnic.push(rows)
        return 0
    if args.cmd == "delete-movements":
        rows, hits = ledger.plan_delete(arnic.snapshot(), args.note_contains)
        for t in hits:
            print(("[dry-run] " if args.dry_run else "") + f"borrar {budgets.money(t['amountMinor'], sym)} · {t.get('note')}")
        if not args.dry_run and hits:
            arnic.push(rows)
        print(f"{len(hits)} movimiento(s)")
        return 0
    if args.cmd == "check":
        snap = arnic.snapshot()
        print(f"API ok: {len(snap['categories'])} categorías, {len(snap['budgets'])} presupuestos, {len(snap['transactions'])} movimientos")
        n = sum(1 for _ in mail_source.fetch_recent(cfg.imap_host, cfg.imap_user, cfg.imap_password, cfg.imap_folder, cfg.bank_senders or ["noreply"], 1))
        print(f"Correo ok ({n} correos recientes del banco)")
        tg.send("✅ Puente de Arnic Finance configurado correctamente.")
        print("Telegram ok")
        return 0


if __name__ == "__main__":
    sys.exit(main())
