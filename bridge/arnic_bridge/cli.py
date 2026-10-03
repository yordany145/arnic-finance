import argparse
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

from . import budgets, config, ledger, mail_source
from .client import Arnic, ApiError
from .parser import NotAPurchase, categorize, parse_purchase
from .state import State
from .telegram import Telegram


def process_mail(mail, cfg, arnic, tg, state, dry_run=False, snapshot=None) -> str:
    """Devuelve 'registrado' | 'omitido' | 'error'. Marca el correo como visto para no repetirlo."""
    key = f"mail:{mail.message_id}"
    if state.has(key):
        return "omitido"
    try:
        p = parse_purchase(mail.subject, mail.body)
    except NotAPurchase:
        state.add(key)  # publicidad, rechazos, etc.: no es un gasto, no insistir
        return "omitido"
    amount = p.amount_minor
    if p.currency == "USD":
        if not cfg.usd_to_local:
            if not dry_run:
                tg.send(f"💳 Consumo en USD de ${amount / 100:,.2f} en {p.merchant}. No lo registré: falta `usd_to_local` en la config.")
                state.add(key)
            return "error"
        amount = round(amount * cfg.usd_to_local)
    category = categorize(p.merchant, cfg.category_rules, cfg.fallback_category)
    if snapshot is not None and ledger.is_duplicate(snapshot, amount, mail.date_ms):
        if not dry_run:
            state.add(key)  # ya estaba registrado: no repetirlo
        return "omitido"
    note = p.merchant + (f" (tarjeta ••{p.card_last4})" if p.card_last4 else "")
    if dry_run:
        print(f"[dry-run] {budgets.money(amount, cfg.currency_symbol)} | {category} | {note}")
        return "registrado"
    try:
        arnic.add_expense(amount, category, note, mail.date_ms, cfg.card_account)
    except ApiError as e:
        tg.send(f"⚠️ No pude registrar {budgets.money(amount, cfg.currency_symbol)} en {p.merchant}: {e}. Lo reintentaré en la próxima corrida.")
        return "error"  # sin marcar: se reintenta
    state.add(key)
    tg.send(f"💳 {budgets.money(amount, cfg.currency_symbol)} · {category}\n{note}")
    return "registrado"


def check_alerts(cfg, arnic, tg, state) -> int:
    now = datetime.now(ZoneInfo(cfg.timezone))
    msgs = budgets.new_alerts(arnic.snapshot(), now, cfg.currency_symbol, state.has)
    for key, text in msgs:
        tg.send(text)
        state.add(key)
    return len(msgs)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="arnic_bridge")
    ap.add_argument("--config")
    sub = ap.add_subparsers(dest="cmd", required=True)
    ing = sub.add_parser("ingest", help="lee el correo del banco, registra gastos y avisa si se cruza un presupuesto")
    ing.add_argument("--dry-run", action="store_true", help="muestra lo que haría sin registrar ni avisar")
    ing.add_argument("--file", help="probar con un .eml guardado en vez de leer el correo")
    rep = sub.add_parser("report", help="manda un reporte por Telegram")
    rep.add_argument("period", choices=["daily", "weekly"])
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

    if args.cmd == "ingest":
        if args.file:
            mails = [mail_source.from_bytes(open(args.file, "rb").read())]
        else:
            mails = mail_source.fetch_recent(cfg.imap_host, cfg.imap_user, cfg.imap_password, cfg.imap_folder, cfg.bank_senders, cfg.lookback_days)
        counts = {"registrado": 0, "omitido": 0, "error": 0}
        snapshot = arnic.snapshot()
        for m in mails:
            counts[process_mail(m, cfg, arnic, tg, state, args.dry_run, snapshot)] += 1
        if counts["registrado"] and not args.dry_run:
            check_alerts(cfg, arnic, tg, state)
        print(counts)
        return 1 if counts["error"] else 0
    if args.cmd == "report":
        now = datetime.now(ZoneInfo(cfg.timezone))
        days, label = (1, "diario") if args.period == "daily" else (7, "semanal")
        tg.send(budgets.report(arnic.snapshot(), now, cfg.currency_symbol, days, label))
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
            print(("[dry-run] " if args.dry_run else "") + f"borrar {budgets.money(t['amountMinor'], cfg.currency_symbol)} · {t.get('note')}")
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
