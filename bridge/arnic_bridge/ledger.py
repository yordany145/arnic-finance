"""Cambios que la API de movimientos no ofrece (crear cuenta, borrar), vía /v1/sync.
Los borrados son lógicos (deletedAt), igual que en la app."""
import time
import uuid

ICONS = {"cash": "💵", "bank": "🏦", "creditCard": "💳", "savings": "🐖", "checking": "🧾"}


def _now() -> int:
    return int(time.time() * 1000)


def plan_account(snapshot: dict, name: str, kind: str, balance_minor: int, now: int | None = None):
    """Devuelve (filas_a_enviar, descripción). Idempotente: no duplica cuenta ni saldo inicial."""
    now = now or _now()
    rows: dict = {"accounts": [], "transactions": []}
    live = [a for a in snapshot["accounts"] if not a.get("deletedAt")]
    account = next((a for a in live if a["name"].strip().lower() == name.strip().lower()), None)
    created = account is None
    if created:
        account = {"id": str(uuid.uuid4()), "name": name, "icon": ICONS[kind], "kind": kind,
                   "sortOrder": max([a.get("sortOrder", 0) for a in live] + [0]) + 1,
                   "createdAt": now, "updatedAt": now, "deletedAt": None}
        rows["accounts"].append(account)
    note = f"Saldo inicial — {account['name']}"
    has_opening = any(t["accountId"] == account["id"] and t.get("note") == note and not t.get("deletedAt") for t in snapshot["transactions"])
    if balance_minor > 0 and not has_opening:
        cat = next((c for c in snapshot["categories"] if c["type"] == "income" and c["name"] == "Otros" and not c.get("deletedAt")), None)
        if cat is None:
            raise ValueError("No encontré la categoría de ingreso 'Otros' en el servidor.")
        rows["transactions"].append({"id": str(uuid.uuid4()), "type": "income", "amountMinor": balance_minor, "categoryId": cat["id"],
                                     "accountId": account["id"], "note": note, "occurredAt": now, "createdAt": now, "updatedAt": now, "deletedAt": None})
    return rows, f"{'crear' if created else 'reusar'} cuenta '{name}' ({kind}); " + ("ingreso inicial" if rows["transactions"] else "sin ingreso nuevo")


def plan_delete(snapshot: dict, needles: list, now: int | None = None):
    """Marca como borrados los movimientos vivos cuya nota contiene alguno de [needles]."""
    now = now or _now()
    keys = [n.lower() for n in needles]
    hits = [t for t in snapshot["transactions"] if not t.get("deletedAt") and any(k in (t.get("note") or "").lower() for k in keys)]
    return {"transactions": [{**t, "deletedAt": now, "updatedAt": now} for t in hits]}, hits
