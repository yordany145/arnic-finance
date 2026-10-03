import sys
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from arnic_bridge import budgets, ledger, mail_source
from arnic_bridge.config import DEFAULT_CATEGORY_RULES
from arnic_bridge.parser import NotAPurchase, categorize, parse_amount, parse_email, parse_purchase


class Parser(unittest.TestCase):
    def test_amounts(self):
        self.assertEqual(parse_amount("1,250.00"), 125000)
        self.assertEqual(parse_amount("1.250,00"), 125000)
        self.assertEqual(parse_amount("500"), 50000)
        self.assertEqual(parse_amount("1,250"), 125000)
        self.assertEqual(parse_amount("99.5"), 9950)

    def test_purchase(self):
        p = parse_purchase("Notificación de consumo", "Se realizó una compra por RD$1,250.00 en SUPERMERCADO NACIONAL con su tarjeta terminada en 4321 el 03/10/2026.")
        self.assertEqual((p.amount_minor, p.currency, p.merchant, p.card_last4), (125000, "LOCAL", "SUPERMERCADO NACIONAL", "4321"))

    BANRESERVAS = (" Notificación de Consumo - Banreservas\n\n| |\n| Notificación de Consumo |\n| Su tarjeta MCS-MULTIMONEDA ••0000 presenta un consumo. |\n\n"
                   "| Monto: |\n| DOP 4,900.00 |\n\n| Estado: |\n| APROBADO |\n\n| Comercio: |\n| ECOPETROLEO LA VEGA LA VEGA DOM |\n\n"
                   "| Fecha de transacción: |\n| 02/10/2026 06:51 PM |\n\n| Número de aprobación: |\n| 524225 |\n")

    def test_banreservas_real_format(self):
        p = parse_purchase("Notificaciones Banreservas", self.BANRESERVAS)
        self.assertEqual((p.amount_minor, p.currency, p.merchant, p.card_last4), (490000, "LOCAL", "ECOPETROLEO LA VEGA LA VEGA DOM", "0000"))
        self.assertEqual(categorize(p.merchant, DEFAULT_CATEGORY_RULES, "Otros"), "Combustible")

    def test_banreservas_not_approved_and_transfers(self):
        with self.assertRaises(NotAPurchase):
            parse_purchase("x", self.BANRESERVAS.replace("APROBADO", "DECLINADA"))
        with self.assertRaises(NotAPurchase):  # transferencias y pagos no son consumos
            parse_purchase("Recibo de la transacción", "¡Transacción realizada! Monto: DOP 24000.00 Transacción: Transferencia a Tercero")
        with self.assertRaises(NotAPurchase):
            parse_purchase("Recibo de la transacción", "¡Pago realizado! Monto: DOP 699.00 Transacción: Pago de Tarjeta de Crédito Propio")

    def test_usd(self):
        p = parse_purchase("Consumo", "Compra por US$12.99 en NETFLIX.COM terminada en 1111.")
        self.assertEqual((p.amount_minor, p.currency), (1299, "USD"))

    def test_rejected_and_ads(self):
        with self.assertRaises(NotAPurchase):
            parse_purchase("Transacción rechazada", "Su compra por RD$500.00 en TIENDA fue rechazada.")
        with self.assertRaises(NotAPurchase):
            parse_purchase("Ofertas", "Hasta 70% de descuento este fin de semana")

    def test_categorize(self):
        self.assertEqual(categorize("SUPERMERCADO NACIONAL", DEFAULT_CATEGORY_RULES, "Otros"), "Comida")
        self.assertEqual(categorize("Cafetería Ñandú", DEFAULT_CATEGORY_RULES, "Otros"), "Comida")
        self.assertEqual(categorize("XYZ 123", DEFAULT_CATEGORY_RULES, "Otros"), "Otros")


BHD = ("| |\n\n| BHD Notificación de Transacciones Mastercard Local # 0000 Detalle de Criterios Te notificamos la transacción realizada con tu "
       "Tarjeta Mastercard Local # 0000 En caso de no reconocer esta transacción, por favor llama. Detalle de Transacciones |\n"
       "| Fecha | Moneda | Monto | Comercio | Estado | Tipo |\n| 21/09/2026 02:12 pm | RD | $3,990.00 | CCC CIBAO ECOMM | Aprobada | Compra |\n")


class Cards(unittest.TestCase):
    def test_bhd_row(self):
        (p,) = parse_email("alertas@bhd.com.do", "BHD Notificación de Transacciones", BHD)
        self.assertEqual((p.amount_minor, p.currency, p.merchant, p.card_last4, p.bank), (399000, "LOCAL", "CCC CIBAO ECOMM", "0000", "bhd"))
        self.assertEqual(datetime.fromtimestamp(p.when_ms / 1000, ZoneInfo("America/Santo_Domingo")), datetime(2026, 9, 21, 14, 12, tzinfo=ZoneInfo("America/Santo_Domingo")))

    def test_bhd_ignores_non_purchases(self):
        for tipo, estado in (("Retiro", "Aprobada"), ("Compra", "Rechazada"), ("Pago", "Aprobada")):
            with self.assertRaises(NotAPurchase):
                parse_email("Alertas@bhd.com.do", "x", BHD.replace("Compra", tipo).replace("Aprobada", estado))
        with self.assertRaises(NotAPurchase):  # transferencias de BHD: no traen tabla de compras
            parse_email("Alertas@bhd.com.do", "Transacciones entre mis productos", "Producto origen: X Monto: RD$ 4000.00")

    def test_banreservas_dispatch(self):
        (p,) = parse_email("notificaciones@banreservas.com", "Notificaciones Banreservas", Parser.BANRESERVAS)
        self.assertEqual((p.bank, p.amount_minor), ("banreservas", 490000))
        with self.assertRaises(NotAPurchase):
            parse_email("NotificacionesTuBancoApp@banreservas.com", "Recibo", Parser.BANRESERVAS)
        with self.assertRaises(NotAPurchase):
            parse_email("notificaciones@banreservas.com", "Notificaciones", "Transferencia Recibida Monto: RD$ 2130.00")
        with self.assertRaises(NotAPurchase):
            parse_email("promo@otro.com", "x", Parser.BANRESERVAS)

    def test_only_configured_credit_cards(self):
        from types import SimpleNamespace
        from arnic_bridge import cli
        sent, added = [], []
        cfg = SimpleNamespace(cards={"bhd": {"account": "Tarjeta BHD", "last4": ["1111"]}}, usd_to_local=None, card_account="", category_rules={}, fallback_category="Otros", currency_symbol="RD$")
        arnic = SimpleNamespace(add_expense=lambda *a: added.append(a))
        tg = SimpleNamespace(send=sent.append)
        state = SimpleNamespace(has=lambda k: False, add=lambda k: None)
        mine = SimpleNamespace(message_id="1", sender="alertas@bhd.com.do", subject="x", body=BHD.replace("0000", "1111"), date_ms=0)
        other = SimpleNamespace(message_id="2", sender="alertas@bhd.com.do", subject="x", body=BHD, date_ms=0)  # tarjeta ••0000
        self.assertEqual(cli.process_mail(mine, cfg, arnic, tg, state), "registrado")
        self.assertEqual(cli.process_mail(other, cfg, arnic, tg, state), "omitido")
        self.assertEqual(len(added), 1)
        self.assertEqual(added[0][4], "Tarjeta BHD")

    def test_usage_and_limit_alerts(self):
        tz = ZoneInfo("America/Santo_Domingo")
        now = datetime(2026, 10, 15, 12, tzinfo=tz)
        t = int(datetime(2026, 10, 10, tzinfo=tz).timestamp() * 1000)
        snap = {"categories": [], "budgets": [], "accounts": [{"id": "a1", "name": "Tarjeta Banreservas"}, {"id": "a2", "name": "Tarjeta BHD"}],
                "transactions": [{"type": "expense", "amountMinor": 1260000, "accountId": "a1", "categoryId": "c", "occurredAt": t},
                                 {"type": "expense", "amountMinor": 500000, "accountId": "a2", "categoryId": "c", "occurredAt": t}]}
        cards = {"banreservas": {"account": "Tarjeta Banreservas", "limit": 15000}, "bhd": {"account": "Tarjeta BHD", "limit": 30000}}
        usage = {b: (spent, lim) for b, _, spent, lim in budgets.card_usage(snap, now, cards)}
        self.assertEqual(usage, {"banreservas": (1260000, 1500000), "bhd": (500000, 3000000)})
        alerts = budgets.card_alerts(snap, now, cards, "RD$", set().__contains__)
        self.assertEqual(len(alerts), 1)  # solo Banreservas pasa del 80% (84%)
        self.assertIn("84%", alerts[0][1])
        self.assertIn("Tarjeta Banreservas", budgets.report(snap, now, "RD$", 7, "semanal", cards))


class Budgets(unittest.TestCase):
    NOW = datetime(2026, 10, 15, 12, tzinfo=ZoneInfo("America/Santo_Domingo"))

    def snap(self, spent):
        t = int(datetime(2026, 10, 10, tzinfo=ZoneInfo("America/Santo_Domingo")).timestamp() * 1000)
        old = int(datetime(2026, 9, 10, tzinfo=ZoneInfo("America/Santo_Domingo")).timestamp() * 1000)
        return {
            "categories": [{"id": "c1", "name": "Comida"}],
            "budgets": [{"id": "b1", "kind": "category", "categoryId": "c1", "amountMinor": 100000}],
            "transactions": [
                {"id": "t1", "type": "expense", "amountMinor": spent, "categoryId": "c1", "occurredAt": t},
                {"id": "t0", "type": "expense", "amountMinor": 999999, "categoryId": "c1", "occurredAt": old},  # mes pasado: no cuenta
                {"id": "t2", "type": "expense", "amountMinor": 999999, "categoryId": "c1", "occurredAt": t, "deletedAt": 1},
            ],
        }

    def test_thresholds_and_dedupe(self):
        seen = set()
        self.assertEqual(budgets.new_alerts(self.snap(70000), self.NOW, "RD$", seen.__contains__), [])
        a = budgets.new_alerts(self.snap(85000), self.NOW, "RD$", seen.__contains__)
        self.assertEqual(len(a), 1)
        self.assertIn("85%", a[0][1])
        seen.add(a[0][0])
        self.assertEqual(budgets.new_alerts(self.snap(86000), self.NOW, "RD$", seen.__contains__), [])  # ya avisado
        b = budgets.new_alerts(self.snap(120000), self.NOW, "RD$", seen.__contains__)
        self.assertEqual(len(b), 1)
        self.assertIn("Te pasaste", b[0][1])

    def test_report(self):
        text = budgets.report(self.snap(85000), self.NOW, "RD$", 7, "semanal")
        self.assertIn("Comida", text)


class Mail(unittest.TestCase):
    def test_eml(self):
        raw = (b"From: Banco <avisos@banco.test>\r\nDate: Sat, 03 Oct 2026 10:00:00 -0400\r\nSubject: Consumo\r\n"
               b"Message-ID: <a@b>\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p>Compra por <b>RD$100.00</b> en CINE</p>")
        m = mail_source.from_bytes(raw)
        self.assertEqual((m.sender, m.message_id), ("avisos@banco.test", "<a@b>"))
        self.assertIn("RD$100.00", m.body)
        self.assertEqual(parse_purchase(m.subject, m.body).merchant, "CINE")


class Ledger(unittest.TestCase):
    SNAP = {"accounts": [{"id": "acc_cash", "name": "Efectivo", "kind": "cash", "sortOrder": 0}],
            "categories": [{"id": "inc_other", "name": "Otros", "type": "income"}],
            "transactions": [{"id": "t1", "type": "expense", "amountMinor": 100, "note": "PRUEBA puente", "accountId": "acc_cash"},
                             {"id": "t2", "type": "expense", "amountMinor": 5, "note": "Cine", "accountId": "acc_cash"}]}

    def test_account_with_opening_balance(self):
        rows, _ = ledger.plan_account(self.SNAP, "Qik ahorros", "savings", 3700000, now=5)
        self.assertEqual(rows["accounts"][0]["kind"], "savings")
        self.assertEqual((rows["transactions"][0]["type"], rows["transactions"][0]["amountMinor"]), ("income", 3700000))
        self.assertEqual(rows["transactions"][0]["accountId"], rows["accounts"][0]["id"])

    def test_idempotent(self):
        rows, _ = ledger.plan_account(self.SNAP, "Qik ahorros", "savings", 3700000, now=5)
        snap = {**self.SNAP, "accounts": self.SNAP["accounts"] + rows["accounts"], "transactions": self.SNAP["transactions"] + rows["transactions"]}
        again, _ = ledger.plan_account(snap, "qik AHORROS", "savings", 3700000)
        self.assertEqual((again["accounts"], again["transactions"]), ([], []))

    def test_duplicate_guard(self):
        snap = {"transactions": [{"type": "expense", "amountMinor": 490000, "occurredAt": 1_000_000, "deletedAt": None}]}
        self.assertTrue(ledger.is_duplicate(snap, 490000, 1_000_000 + 60_000))
        self.assertFalse(ledger.is_duplicate(snap, 490000, 1_000_000 + 3_600_000))
        self.assertFalse(ledger.is_duplicate(snap, 100, 1_000_000))
        snap["transactions"][0]["deletedAt"] = 5
        self.assertFalse(ledger.is_duplicate(snap, 490000, 1_000_000))

    def test_delete_matches_only_notes(self):
        rows, hits = ledger.plan_delete(self.SNAP, ["prueba"], now=9)
        self.assertEqual([t["id"] for t in hits], ["t1"])
        self.assertEqual(rows["transactions"][0]["deletedAt"], 9)


if __name__ == "__main__":
    unittest.main()
