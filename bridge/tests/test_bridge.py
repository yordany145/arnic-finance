import sys
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from arnic_bridge import budgets, cards as cardlib, export, insights, ledger, mail_source
from arnic_bridge.config import DEFAULT_CATEGORY_RULES
from arnic_bridge.parser import NotAPurchase, categorize, foreign_country, merchant_key, parse_amount, parse_email, parse_purchase, parse_qik_deposit


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

    def test_bhd_html_layout(self):
        """El correo real (HTML) deja cada celda en su propia línea, sin barras."""
        html = ("BHD Notificación de Transacciones Mastercard Local # 1111 Te notificamos la transacción realizada con tu Tarjeta Mastercard Local # 1111 \n"
                "Detalle de Transacciones \n \n Fecha \n \n Moneda \n \n Monto \n \n Comercio \n \n Estado \n \n Tipo \n \n"
                " 20/09/2026 12:14 pm \n \n RD \n \n $2,000.00 \n \n ECO PETROLEO ALMONTE L \n \n Aprobada \n \n Compra \n \n"
                " 20/09/2026 12:20 pm \n \n RD \n \n $50.00 \n \n OTRO COMERCIO \n \n Rechazada \n \n Compra \n \n Ahora, tus Tarjetas BHD")
        (p,) = parse_email("alertas@bhd.com.do", "BHD Notificación de Transacciones", html)
        self.assertEqual((p.amount_minor, p.merchant, p.card_last4), (200000, "ECO PETROLEO ALMONTE L", "1111"))
        self.assertEqual(categorize(p.merchant, DEFAULT_CATEGORY_RULES, "Otros"), "Combustible")

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


TZ = ZoneInfo("America/Santo_Domingo")


def _ms(y, m, d, h=12):
    return int(datetime(y, m, d, h, tzinfo=TZ).timestamp() * 1000)


class CardCycles(unittest.TestCase):
    def test_cycle_bounds(self):
        from datetime import date
        self.assertEqual(cardlib.cycle_bounds(date(2026, 10, 3), 15), (date(2026, 9, 16), date(2026, 10, 15)))
        self.assertEqual(cardlib.cycle_bounds(date(2026, 10, 15), 15), (date(2026, 9, 16), date(2026, 10, 15)))  # el día del corte aún es del ciclo viejo
        self.assertEqual(cardlib.cycle_bounds(date(2026, 10, 16), 15), (date(2026, 10, 16), date(2026, 11, 15)))
        self.assertEqual(cardlib.cycle_bounds(date(2026, 12, 20), 15), (date(2026, 12, 16), date(2027, 1, 15)))  # cruza de año
        self.assertEqual(cardlib.cycle_bounds(date(2026, 3, 5), 31), (date(2026, 3, 1), date(2026, 3, 31)))  # corte 31: el de febrero fue el 28, así que marzo empieza el 1
        self.assertEqual(cardlib.cycle_bounds(date(2026, 10, 3), None), (date(2026, 10, 1), date(2026, 10, 31)))

    def test_next_due(self):
        from datetime import date
        self.assertEqual(cardlib.next_due(date(2026, 10, 3), 5), date(2026, 10, 5))
        self.assertEqual(cardlib.next_due(date(2026, 10, 6), 5), date(2026, 11, 5))
        self.assertEqual(cardlib.next_due(date(2026, 1, 31), 30), date(2026, 2, 28))
        self.assertIsNone(cardlib.next_due(date(2026, 10, 3), None))

    SNAP = {"accounts": [{"id": "a1", "name": "Tarjeta Banreservas"}, {"id": "a2", "name": "Tarjeta BHD"}], "categories": [], "budgets": [],
            "transactions": [{"type": "expense", "amountMinor": 1260000, "accountId": "a1", "categoryId": "c", "occurredAt": _ms(2026, 10, 10)},
                             {"type": "expense", "amountMinor": 999900, "accountId": "a1", "categoryId": "c", "occurredAt": _ms(2026, 9, 10)},  # ciclo anterior
                             {"type": "expense", "amountMinor": 500000, "accountId": "a2", "categoryId": "c", "occurredAt": _ms(2026, 10, 10)}]}
    LOCAL = {"banreservas": {"account": "Tarjeta Banreservas", "limit": 15000, "last4": ["2110"]}, "bhd": {"account": "Tarjeta BHD", "limit": 30000, "last4": ["8866"]}}

    def test_server_config_overrides_local(self):
        server = {"cards": [{"accountId": "a1", "limitMinor": 2000000, "cutDay": 20, "dueDay": 8}]}
        eff = cardlib.effective_cards(self.LOCAL, self.SNAP, server)
        self.assertEqual((eff["banreservas"]["limit_minor"], eff["banreservas"]["cut_day"], eff["banreservas"]["due_day"]), (2000000, 20, 8))
        self.assertEqual((eff["bhd"]["limit_minor"], eff["bhd"]["cut_day"]), (3000000, None))  # sin dato en el servidor: lo local
        self.assertEqual(cardlib.effective_cards(self.LOCAL, self.SNAP, None)["banreservas"]["limit_minor"], 1500000)

    def test_usage_by_cycle_and_alerts(self):
        server = {"cards": [{"accountId": "a1", "limitMinor": 1500000, "cutDay": 15, "dueDay": 5}]}
        now = datetime(2026, 10, 15, 12, tzinfo=TZ)
        rows = {r["bank"]: r for r in cardlib.usage(self.SNAP, now, cardlib.effective_cards(self.LOCAL, self.SNAP, server))}
        self.assertEqual(rows["banreservas"]["spent"], 1260000)  # el consumo del 10/sep es de otro ciclo (16/sep–15/oct lo incluye si cae dentro)
        self.assertEqual(rows["banreservas"]["available"], 240000)
        alerts = cardlib.alerts(list(rows.values()), "RD$", set().__contains__)
        self.assertEqual(len(alerts), 1)
        self.assertIn("84%", alerts[0][1])
        self.assertIn("Disponible", alerts[0][1])

    def test_due_reminders(self):
        from datetime import date
        rows = [{"bank": "bhd", "account": "Tarjeta BHD", "due": date(2026, 10, 5)}]
        seen = set()
        self.assertEqual(len(cardlib.due_reminders(rows, seen.__contains__, date(2026, 10, 2))), 1)  # 3 días
        self.assertEqual(cardlib.due_reminders(rows, seen.__contains__, date(2026, 10, 3)), [])  # 2 días: no toca
        self.assertIn("mañana", cardlib.due_reminders(rows, seen.__contains__, date(2026, 10, 4))[0][1])
        self.assertIn("hoy", cardlib.due_reminders(rows, seen.__contains__, date(2026, 10, 5))[0][1])
        key, _ = cardlib.due_reminders(rows, seen.__contains__, date(2026, 10, 5))[0]
        seen.add(key)
        self.assertEqual(cardlib.due_reminders(rows, seen.__contains__, date(2026, 10, 5)), [])  # sin repetir


QIK_DEPOSIT = ("¡Hola Yordany Fern&aacute;ndez Caraballo! Hola Yordany, has recibido un depósito en tu cuenta Qik de manera satisfactoria.\n"
               "<table><tbody><tr><td>Fecha</td><td>2026-10-31</td></tr><tr><td>Entidad origen</td><td>BANCO DE RESERVAS</td></tr>"
               "<tr><td>Monto</td><td>30,000.00</td></tr><tr><td>Método de envío</td><td>ACH</td></tr></tbody></table>")


class Salary(unittest.TestCase):
    SALARY = {"amount": 30000, "tolerance_pct": 10, "origin_contains": ["reserva"], "account": "Qik ahorros", "category": "Salario"}

    def test_parse_qik_deposit_html_and_cells(self):
        inc = parse_qik_deposit("Yordany, has recibido un depósito a tu cuenta Qik.", QIK_DEPOSIT)
        self.assertEqual((inc.amount_minor, inc.origin), (3000000, "BANCO DE RESERVAS"))
        cells = "has recibido un depósito\n Fecha \n 2026-10-31 \n Entidad origen \n BANCO BHD LEON \n Monto \n 25,000.00 \n"
        self.assertEqual(parse_qik_deposit("x", cells).origin, "BANCO BHD LEON")
        with self.assertRaises(NotAPurchase):
            parse_qik_deposit("Yordany, tu transferencia ACH fue procesada.", "tu transferencia ACH desde tu Cuenta Qik hacia otro banco fue enviada")

    def test_only_salary_from_banreservas_is_income(self):
        from types import SimpleNamespace
        from arnic_bridge import cli
        added, sent = [], []
        cfg = SimpleNamespace(salary=self.SALARY, currency_symbol="RD$")
        arnic = SimpleNamespace(add_income=lambda *a: added.append(a))
        tg, state = SimpleNamespace(send=sent.append), SimpleNamespace(has=lambda k: False, add=lambda k: None)
        mail = lambda mid, body: SimpleNamespace(message_id=mid, sender="transacciones@mail.qik.com.do", subject="has recibido un depósito", body=body, date_ms=_ms(2026, 10, 31))
        self.assertEqual(cli.process_mail(mail("1", QIK_DEPOSIT), cfg, arnic, tg, state, snapshot={"transactions": []}), "registrado")
        self.assertEqual((added[0][0], added[0][1], added[0][4]), (3000000, "Salario", "Qik ahorros"))
        self.assertIn("Sueldo recibido", sent[0])
        # otro banco, o un monto que no se parece al sueldo: se ignora en silencio
        self.assertEqual(cli.process_mail(mail("2", QIK_DEPOSIT.replace("BANCO DE RESERVAS", "BANCO BHD LEON")), cfg, arnic, tg, state, snapshot={"transactions": []}), "omitido")
        self.assertEqual(cli.process_mail(mail("3", QIK_DEPOSIT.replace("30,000.00", "4,500.00")), cfg, arnic, tg, state, snapshot={"transactions": []}), "omitido")
        # el mismo depósito leído dos veces no se duplica
        dup = {"transactions": [{"type": "income", "amountMinor": 3000000, "occurredAt": _ms(2026, 10, 31), "deletedAt": None}]}
        self.assertEqual(cli.process_mail(mail("4", QIK_DEPOSIT), cfg, arnic, tg, state, snapshot=dup), "omitido")
        self.assertEqual(len(added), 1)

    def test_salary_tolerance(self):
        from arnic_bridge.cli import _is_salary
        from arnic_bridge.parser import Income
        self.assertTrue(_is_salary(Income(3200000, "BANRESERVAS"), self.SALARY))  # +6.7%
        self.assertFalse(_is_salary(Income(3400000, "BANRESERVAS"), self.SALARY))
        self.assertFalse(_is_salary(Income(3000000, "BANCO POPULAR"), self.SALARY))
        self.assertFalse(_is_salary(Income(3000000, "BANRESERVAS"), {}))


class Insights(unittest.TestCase):
    def snap(self, amounts, extra=None):
        tx = [{"id": f"t{i}", "type": "expense", "amountMinor": a, "categoryId": "c1", "note": "SUPERMERCADO NACIONAL (tarjeta ••1111)",
               "occurredAt": _ms(2026, 10, 1 + i), "updatedAt": i, "deletedAt": None} for i, a in enumerate(amounts)]
        return {"transactions": tx + (extra or []), "categories": [{"id": "c1", "name": "Comida"}, {"id": "c2", "name": "Compras"}]}

    def test_unusual(self):
        s = self.snap([80000] * 6)
        self.assertEqual(insights.unusual_reasons(s, "SUPERMERCADO NACIONAL", 90000), [])
        self.assertTrue(any("extranjero" in r for r in insights.unusual_reasons(s, "UBER EATS Amsterdam NLD", 50000)))
        self.assertTrue(any("monto alto" in r for r in insights.unusual_reasons(s, "SUPERMERCADO NACIONAL", 600000)))
        self.assertTrue(any("nuevo" in r for r in insights.unusual_reasons(s, "TIENDA RARA", 400000)))
        self.assertEqual(insights.unusual_reasons(s, "TIENDA RARA", 20000), [])  # nuevo pero barato
        self.assertEqual(insights.unusual_reasons(self.snap([80000] * 2), "TIENDA RARA", 900000), [])  # poca historia: no se juzga monto ni novedad
        self.assertEqual(foreign_country("HUMMUS SANTIAGO CENTER SANTIAGO DOM"), None)
        self.assertEqual(foreign_country("PAYPAL *HOSTINGER 4029357733 USA"), "USA")

    def test_learn_categories(self):
        s = self.snap([1000])
        self.assertEqual({k: v for k, v in insights.learn_categories(s, {"Comida": ["supermerc"]}, "Otros").items() if v}, {})  # categoría automática: nada que aprender
        s["transactions"][0]["categoryId"] = "c2"  # el usuario la cambió a Compras
        self.assertEqual(insights.learn_categories(s, {"Comida": ["supermerc"]}, "Otros"), {"SUPERMERCADO NACIONAL": "Compras"})
        s["transactions"].append({**s["transactions"][0], "id": "t9", "categoryId": "c1", "updatedAt": 99})  # luego la devolvió a Comida
        self.assertEqual(insights.learn_categories(s, {"Comida": ["supermerc"]}, "Otros"), {"SUPERMERCADO NACIONAL": None})

    def test_merchant_key(self):
        self.assertEqual(merchant_key("ECOPETROLEO LA VEGA LA VEGA DOM (tarjeta ••2110)"), "ECOPETROLEO LA VEGA LA VEGA")
        self.assertEqual(merchant_key("PAYPAL *SPOTIFY*P47346"), "PAYPAL SPOTIFY P")
        # el mismo comercio visto por Banreservas (con número y país) y por BHD tiene la misma clave
        self.assertEqual(merchant_key("PAYPAL *MIKROWISP 35314369001 LUX"), merchant_key("PAYPAL *MIKROWISP"))
        self.assertEqual(merchant_key("USA"), "USA")  # un comercio que solo se llama como un país no se vacía

    def test_subscriptions(self):
        ev = [("SPOTIFY", "PAYPAL *SPOTIFY", 21798, _ms(2026, 8, 23)), ("SPOTIFY", "PAYPAL *SPOTIFY", 21798, _ms(2026, 9, 23)),
              ("TEXACO", "TEXACO", 200000, _ms(2026, 9, 1)), ("TEXACO", "TEXACO", 460000, _ms(2026, 9, 9)),  # irregular: no es suscripción
              ("UNA", "UNA SOLA VEZ", 5000, _ms(2026, 9, 3))]
        found = insights.detect_subscriptions(ev, TZ)
        self.assertEqual([s["label"] for s in found], ["PAYPAL *SPOTIFY"])
        # compras sueltas de otro monto en medio no estropean un cobro mensual real
        noisy = [("HOST", "PAYPAL *HOSTINGER", 121142, _ms(2026, 8, 15)), ("HOST", "PAYPAL *HOSTINGER", 252018, _ms(2026, 9, 3)),
                 ("HOST", "PAYPAL *HOSTINGER", 62018, _ms(2026, 6, 15)), ("HOST", "PAYPAL *HOSTINGER", 121142, _ms(2026, 9, 15))]
        got = insights.detect_subscriptions(noisy, TZ)
        self.assertEqual((len(got), got[0]["charges"], got[0]["amount"]), (1, 2, 121142))
        # tres meses seguidos: la cadena los cuenta
        three = [("N", "NETFLIX", 79900, _ms(2026, 7, 5)), ("N", "NETFLIX", 79900, _ms(2026, 8, 5)), ("N", "NETFLIX", 79900, _ms(2026, 9, 5))]
        self.assertEqual(insights.detect_subscriptions(three, TZ)[0]["charges"], 3)
        self.assertEqual(datetime.fromtimestamp(found[0]["next"] / 1000, TZ).date().isoformat(), "2026-10-23")
        # una suscripción que dejó de cobrarse hace meses no se propone como "próximo cobro" pasado
        self.assertEqual(insights.detect_subscriptions(ev, TZ, _ms(2026, 12, 20)), [])
        self.assertEqual(len(insights.detect_subscriptions(ev, TZ, _ms(2026, 10, 1))), 1)


class Reports(unittest.TestCase):
    SNAP = {"accounts": [{"id": "a1", "name": "Qik ahorros"}, {"id": "a2", "name": "Tarjeta BHD"}],
            "categories": [{"id": "c1", "name": "Comida"}, {"id": "c2", "name": "Salario"}], "budgets": [],
            "transactions": [{"type": "income", "amountMinor": 3000000, "accountId": "a1", "categoryId": "c2", "note": "Sueldo", "occurredAt": _ms(2026, 10, 1)},
                             {"type": "expense", "amountMinor": 150000, "accountId": "a2", "categoryId": "c1", "note": "BURGER KING", "occurredAt": _ms(2026, 10, 3)},
                             {"type": "expense", "amountMinor": 99900, "accountId": "a2", "categoryId": "c1", "note": "AGOSTO", "occurredAt": _ms(2026, 9, 3)}]}

    def test_summary(self):
        now = datetime(2026, 10, 15, tzinfo=TZ)
        text = budgets.summary_text(self.SNAP, now, "RD$", "month", category="comida")
        self.assertIn("gastos RD$1,500.00", text)
        self.assertIn("ingresos RD$0.00", text)
        self.assertIn("ingresos RD$30,000.00", budgets.summary_text(self.SNAP, now, "RD$", "month", account="Qik ahorros"))

    def test_goals_and_balance(self):
        lines = budgets.goals_lines(self.SNAP, [{"name": "Fondo", "account": "qik ahorros", "target": 60000}], "RD$")
        self.assertIn("RD$30,000.00 / RD$60,000.00 (50%)", lines[1])
        self.assertEqual(budgets.goals_lines(self.SNAP, [], "RD$"), [])

    def test_monthly_workbook_and_xlsx(self):
        import tempfile
        import zipfile
        first = datetime(2026, 10, 1, tzinfo=TZ)
        sheets, text = budgets.monthly_workbook(self.SNAP, first, "RD$", [], [])
        self.assertIn("gastos RD$1,500.00", text)  # la compra de septiembre no entra
        self.assertEqual(len(sheets[1][1]), 3)  # encabezado + 2 movimientos de octubre
        with tempfile.TemporaryDirectory() as d:
            path = f"{d}/r.xlsx"
            export.write_xlsx(path, sheets)
            with zipfile.ZipFile(path) as z:
                self.assertIsNone(z.testzip())
                self.assertIn("BURGER KING", z.read("xl/worksheets/sheet2.xml").decode())
                self.assertIn('name="Movimientos"', z.read("xl/workbook.xml").decode())


if __name__ == "__main__":
    unittest.main()
