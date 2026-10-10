"""Tasa de cambio USD→DOP, para los consumos en dólares que el banco no convierte.

Se consulta una API pública gratuita (sin clave) y se guarda en caché varias horas: la tasa
no cambia mucho en un día y el puente revisa el correo cada 5 minutos, así que sin caché
haría decenas de peticiones diarias para nada. Si no hay internet o las dos fuentes fallan,
se usa la última tasa en caché aunque esté vieja — mejor una tasa de ayer que no registrar
el gasto — y se avisa de que está vieja. Si nunca se pudo obtener ninguna, se devuelve
`None` y quien llama decide (hoy: avisar por Telegram y reintentar en la próxima corrida).
"""
import json
import time
import urllib.error
import urllib.request

# Dos fuentes independientes (ninguna pide clave); si la primera falla o no publica DOP, la segunda.
_SOURCES = ("https://open.er-api.com/v6/latest/USD", "https://api.exchangerate-api.com/v4/latest/USD")

DEFAULT_MAX_AGE_HOURS = 6


def _fetch_live(timeout: float = 10) -> float | None:
    for url in _SOURCES:
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                data = json.loads(r.read())
            rate = (data.get("rates") or {}).get("DOP")
            if isinstance(rate, (int, float)) and rate > 0:
                return float(rate)
        except (urllib.error.URLError, TimeoutError, ValueError, OSError):
            continue  # se intenta la siguiente fuente; si ninguna responde, el caller usa la caché
    return None


def _read_cache(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def get_usd_to_dop(cache_path: str, max_age_hours: float = DEFAULT_MAX_AGE_HOURS, now: float | None = None) -> tuple:
    """(tasa, es_de_caché_vieja). `(None, False)` si nunca se pudo conseguir ninguna tasa."""
    now = now if now is not None else time.time()
    cache = _read_cache(cache_path)
    if cache.get("rate") and (now - cache.get("fetched_at", 0)) < max_age_hours * 3600:
        return cache["rate"], False

    rate = _fetch_live()
    if rate:
        try:
            with open(cache_path, "w") as f:
                json.dump({"rate": rate, "fetched_at": now}, f)
        except OSError:
            pass  # sin caché persistida no pasa nada: se reintenta fetch en la próxima corrida
        return rate, False

    if cache.get("rate"):
        return cache["rate"], True  # sin internet ahora: mejor una tasa vieja que no registrar el gasto
    return None, False
