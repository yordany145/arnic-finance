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
