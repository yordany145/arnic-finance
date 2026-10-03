import sys
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from arnic_bridge import budgets, ledger, mail_source
from arnic_bridge.config import DEFAULT_CATEGORY_RULES
from arnic_bridge.parser import NotAPurchase, categorize, parse_amount, parse_purchase


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

    def test_delete_matches_only_notes(self):
        rows, hits = ledger.plan_delete(self.SNAP, ["prueba"], now=9)
        self.assertEqual([t["id"] for t in hits], ["t1"])
        self.assertEqual(rows["transactions"][0]["deletedAt"], 9)


if __name__ == "__main__":
    unittest.main()
