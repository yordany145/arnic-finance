#!/usr/bin/env python3
"""Asistente de configuración: pide lo mínimo, guarda con permisos 600 y prueba todo."""
import getpass
import json
import os
import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
target = here / "config.local.json"


def ask(prompt, default="", secret=False):
    shown = f" [{default}]" if default else ""
    value = (getpass.getpass if secret else input)(f"{prompt}{shown}: ").strip()
    return value or default


print("=== Configuración del puente de Arnic Finance ===\n")
cfg = json.loads(target.read_text()) if target.exists() else {}
cfg["server_url"] = ask("URL del servidor", cfg.get("server_url", "https://arnic-finance-api.onrender.com"))
print("\nLa API key está en la app: Ajustes > Integraciones > Ver API key.")
cfg["api_key"] = ask("API key (no se mostrará al escribir)", cfg.get("api_key", ""), secret=True)
print("\nCorreo donde llegan los avisos de la tarjeta (Gmail).")
cfg["imap_user"] = ask("Gmail", cfg.get("imap_user", ""))
print("Contraseña de aplicación de Google (16 letras): myaccount.google.com/apppasswords")
cfg["imap_password"] = ask("Contraseña de aplicación", cfg.get("imap_password", ""), secret=True).replace(" ", "")
senders = ask("Correo(s) del banco que envían los avisos, separados por coma", ",".join(cfg.get("bank_senders", [])))
cfg["bank_senders"] = [s.strip() for s in senders.split(",") if s.strip()]
cfg["card_account"] = ask("Nombre de la cuenta de la tarjeta en la app (Enter = la predeterminada)", cfg.get("card_account", ""))

target.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
os.chmod(target, 0o600)
print(f"\nGuardado en {target} (solo legible por usted). Probando conexiones…\n")
sys.exit(subprocess.call([sys.executable, "-m", "arnic_bridge", "check"], cwd=here))
