"""Extrae un gasto de un aviso de consumo de tarjeta.

Heurístico a propósito: cada banco redacta distinto. Cuando llegue un correo real
del banco, se añade su caso a tests/test_parser.py y se ajustan los patrones aquí.
"""
import re
import unicodedata
from dataclasses import dataclass


@dataclass
class Purchase:
    amount_minor: int
    currency: str  # 'LOCAL' | 'USD'
    merchant: str
    card_last4: str | None
    bank: str = ""
    when_ms: int | None = None  # fecha del cuerpo, si el aviso la trae con hora exacta


class NotAPurchase(Exception):
    """El correo no es un consumo registrable (rechazo, reverso, publicidad…)."""


_SKIP = re.compile(r"rechaz|declinad|denegad|reverso|reversad|devoluci|reembolso|cancelad", re.I)
_BUY = re.compile(r"presenta un consumo|notificaci[oó]n de consumo|\bconsumo\b|\bcompra\b", re.I)
_AMOUNT = re.compile(r"(RD\s?\$|US\s?\$|USD|DOP|\$)\s?(\d[\d.,]*\d|\d)", re.I)
_MERCHANT = [
    re.compile(r"(?:comercio|establecimiento|merchant)\s*:\s*\n?\s*([^\n]+)", re.I),
    re.compile(r"\b(?:en|at)\s+([A-Z0-9][^\n.,;]{2,50}?)(?=\s+(?:con|el|a las|con su|using|on)\b|[.,;\n]|$)"),
]
_CARD = re.compile(r"(?:terminad[ao]\s+en|termina\s+en|ending\s+(?:in|with)|\*{2,}|•{2,}|x{2,})\s*(\d{4})", re.I)


def parse_amount(text: str) -> int:
    """'1,250.00' / '1.250,00' / '1250' -> centavos."""
    s = text.strip()
    if "," in s and "." in s:
        dec = "," if s.rfind(",") > s.rfind(".") else "."
    elif "," in s:
        dec = "," if re.search(r",\d{2}$", s) else None
    elif "." in s:
        dec = "." if re.search(r"\.\d{1,2}$", s) else None
    else:
        dec = None
    if dec:
        whole, frac = s.rsplit(dec, 1)
        whole = re.sub(r"[.,]", "", whole)
        return int(whole) * 100 + int(frac.ljust(2, "0")[:2])
    return int(re.sub(r"[.,]", "", s)) * 100


def _strip_accents(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def _flatten(body: str) -> str:
    """Los correos del banco son tablas ('| Comercio: |' / '| VALOR |'): quita las barras y las líneas vacías."""
    lines = (re.sub(r"\s+", " ", ln.replace("|", " ")).strip() for ln in body.splitlines())
    return "\n".join(ln for ln in lines if ln)


def parse_purchase(subject: str, body: str) -> Purchase:
    body = _flatten(body)
    text = f"{subject}\n{body}"
    estado = re.search(r"estado\s*:\s*\n?\s*([^\n]+)", body, re.I)
    if estado and not re.search(r"aprobad", estado.group(1), re.I):
        raise NotAPurchase(f"estado {estado.group(1).strip()}")
    if _SKIP.search(text):
        raise NotAPurchase("rechazo, reverso o devolución")
    if not _BUY.search(text):
        raise NotAPurchase("no parece un consumo")
    after_monto = re.search(r"monto\s*:", text, re.I)
    m = (_AMOUNT.search(text, after_monto.end()) if after_monto else None) or _AMOUNT.search(text)
    if not m:
        raise NotAPurchase("sin monto")
    sym = re.sub(r"\s", "", m.group(1)).upper()
    currency = "USD" if sym in ("US$", "USD") else "LOCAL"
    amount = parse_amount(m.group(2))
    if amount <= 0:
        raise NotAPurchase("monto cero")
    merchant = ""
    for pat in _MERCHANT:
        mm = pat.search(text)
        if mm:
            merchant = re.sub(r"\s+", " ", mm.group(1)).strip(" -:*")
            break
    merchant = re.split(r"\s+(?:Fecha de transacci)", merchant)[0].strip()
    card = _CARD.search(text)
    return Purchase(amount, currency, merchant or "Comercio desconocido", card.group(1) if card else None)


def categorize(merchant: str, rules: dict, fallback: str) -> str:
    haystack = _strip_accents(merchant).lower()
    for category, keywords in rules.items():
        if any(_strip_accents(k).lower() in haystack for k in keywords):
            return category
    return fallback


_BHD_DATE = re.compile(r"^(\d{2})/(\d{2})/(\d{4})\s+(\d{1,2}):(\d{2})\s*([ap]m)$", re.I)
_BHD_CARD = re.compile(r"Tarjeta[^#\n]*#\s*(\d{4})", re.I)


def parse_bhd(body: str) -> list:
    """Filas de 'Detalle de Transacciones' de BHD. Solo compras aprobadas; el resto (retiros, pagos, reversos) se ignora.

    La tabla llega de dos maneras según de dónde se lea el correo: con barras ('| celda | celda |') o, en el HTML
    real, con cada celda en su propia línea. Se aplanan ambas a una lista de celdas y se buscan filas de 6:
    fecha, moneda, monto, comercio, estado, tipo."""
    from datetime import datetime, timedelta, timezone
    card = _BHD_CARD.search(body)
    cells = [c.strip() for c in re.split(r"[|\n]", body) if c.strip()]
    out = []
    for k, cell in enumerate(cells):
        m = _BHD_DATE.match(cell)
        if not m or k + 5 >= len(cells):
            continue
        cur, amount, merchant, estado, tipo = cells[k + 1 : k + 6]
        if not re.search(r"aprobad", estado, re.I) or not re.fullmatch(r"compra|consumo|goods services( with cash back)?", tipo, re.I) or not re.fullmatch(r"[A-Za-z]{2,3}", cur):
            continue
        digits = re.search(r"[\d.,]*\d", amount)
        minor = parse_amount(digits.group(0)) if digits else 0
        if minor <= 0:
            continue
        d, mo, y, hh, mi, ap = m.groups()
        hour = int(hh) % 12 + (12 if ap.lower() == "pm" else 0)
        local = datetime(int(y), int(mo), int(d), hour, int(mi), tzinfo=timezone(timedelta(hours=-4)))  # hora de República Dominicana
        out.append(Purchase(minor, "USD" if cur.upper().startswith("US") else "LOCAL", re.sub(r"\s+", " ", merchant).strip(),
                            card.group(1) if card else None, "bhd", int(local.timestamp() * 1000)))
    return out


def parse_email(sender: str, subject: str, body: str) -> list:
    """Compras que contiene un correo. Solo se reconocen los avisos de consumo de tarjeta de crédito de cada banco."""
    if sender.endswith("@bhd.com.do"):
        found = parse_bhd(body)
        if not found:
            raise NotAPurchase("aviso de BHD sin compra aprobada")
        return found
    if sender.endswith("@banreservas.com"):
        if "NotificacionesTuBancoApp" in sender:
            raise NotAPurchase("transferencias y pagos")
        p = parse_purchase(subject, body)
        p.bank = "banreservas"
        return [p]
    raise NotAPurchase("remitente no soportado")


@dataclass
class Income:
    amount_minor: int
    origin: str
    when_ms: int | None = None


def _clean_cells(body: str) -> list:
    """Celdas de una tabla venga como HTML crudo, texto con barras o una celda por línea."""
    import html as _html
    text = _html.unescape(re.sub(r"<[^>]+>", "\n", body))
    return [re.sub(r"\s+", " ", c).strip() for c in re.split(r"[|\n]", text) if c.strip()]


def parse_qik_deposit(subject: str, body: str) -> Income:
    """Aviso de Qik 'has recibido un depósito': trae fecha, entidad de origen y monto, pero NO la descripción
    que el usuario escribe en la transferencia (Qik no la incluye), así que el sueldo se reconoce por origen + monto."""
    if not re.search(r"recibido un dep[oó]sito", f"{subject}\n{body}", re.I):
        raise NotAPurchase("no es un depósito recibido")
    cells = _clean_cells(body)

    def after(label: str):
        for i, c in enumerate(cells):
            if c.lower() == label and i + 1 < len(cells):
                return cells[i + 1]
        return None

    amount, origin = after("monto"), after("entidad origen")
    digits = re.search(r"\d[\d.,]*", amount or "")
    if not digits or not origin:
        raise NotAPurchase("depósito sin monto u origen legible")
    minor = parse_amount(digits.group(0))
    if minor <= 0:
        raise NotAPurchase("monto cero")
    return Income(minor, origin)


_COUNTRIES = set("""USA NLD GBR DEU HKG IRL ESP FRA ITA CAN MEX PAN COL BRA ARG CHL PER CHN JPN KOR SGP AUS CHE SWE LUX EST LTU POL PRT
CYP ISR ARE IND TWN HUN CZE DNK NOR FIN BEL AUT PRI JAM CRI GTM ECU URY VEN TUR UKR ROU BGR MLT LVA""".split())


def foreign_country(merchant: str) -> str | None:
    """Los avisos de Banreservas terminan el comercio con el código ISO del país (DOM = local)."""
    last = merchant.strip().split(" ")[-1].upper() if merchant.strip() else ""
    return last if last in _COUNTRIES else None


def merchant_key(text: str) -> str:
    """Clave estable de un comercio para compararlo entre compras: sin tarjeta, acentos, números ni país local."""
    base = text.split(" (tarjeta")[0]
    base = re.sub(r"[^A-Z ]", " ", _strip_accents(base).upper())
    tokens = [t for t in base.split() if t not in ("DOM", "PENDING")]
    if len(tokens) > 1 and tokens[-1] in _COUNTRIES:
        tokens.pop()  # Banreservas termina el comercio con el país (LUX, USA…); BHD no: sin esto el mismo comercio salía con dos claves
    return " ".join(tokens)
