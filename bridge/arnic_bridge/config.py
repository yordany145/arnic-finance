import json
import os
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_CATEGORY_RULES = {
    "Comida": ["supermerc", "colmado", "restaur", "pizza", "burger", "kfc", "mcdonald", "cafe", "panader", "sirena", "nacional", "jumbo", "bravo", "ubereats", "pedidosya"],
    "Combustible": ["gasolin", "combustible", "shell", "texaco", "esso", "sunix", "isla", "total"],
    "Transporte": ["uber", "indrive", "taxi", "peaje", "metro"],
    "Compras": ["amazon", "shein", "temu", "tienda", "plaza", "ikea", "walmart", "aliexpress"],
    "Entretenimiento": ["cine", "steam", "playstation", "xbox", "nvidia", "twitch", "bar ", "disco"],
    "Salud": ["farmacia", "clinica", "hospital", "laborator", "medic", "carol"],
    "Servicios": ["claro", "altice", "edesur", "edeeste", "edenorte", "caasd", "internet", "wind", "viva"],
    "Suscripciones": ["netflix", "spotify", "youtube", "disney", "hbo", "prime video", "openai", "anthropic", "apple.com", "google"],
    "Educación": ["udemy", "coursera", "universidad", "colegio", "libreria"],
    "Hogar": ["ferreter", "muebl", "hogar", "epa"],
}


@dataclass
class Config:
    server_url: str
    api_key: str
    imap_host: str = "imap.gmail.com"
    imap_user: str = ""
    imap_password: str = ""
    imap_folder: str = "INBOX"
    bank_senders: list = field(default_factory=list)
    lookback_days: int = 3
    timezone: str = "America/Santo_Domingo"
    currency_symbol: str = "RD$"
    usd_to_local: float | None = None
    card_account: str = ""
    fallback_category: str = "Otros"
    category_rules: dict = field(default_factory=lambda: dict(DEFAULT_CATEGORY_RULES))
    telegram_config_path: str = "/home/yordany/Escritorio/AI/telegram_bot/config.json"
    state_path: str = ""


def load(path: str | None = None) -> Config:
    path = Path(path or os.environ.get("ARNIC_BRIDGE_CONFIG") or Path(__file__).resolve().parent.parent / "config.local.json")
    if not path.exists():
        raise SystemExit(f"Falta {path}. Copia config.example.json a config.local.json y rellénalo.")
    if path.stat().st_mode & 0o077:
        raise SystemExit(f"{path} contiene secretos: ejecuta `chmod 600 {path}`.")
    raw = json.loads(path.read_text())
    rules = dict(DEFAULT_CATEGORY_RULES)
    rules.update(raw.pop("category_rules", {}))
    cfg = Config(**raw, category_rules=rules)
    if not cfg.state_path:
        cfg.state_path = str(path.parent / "state.db")
    return cfg
