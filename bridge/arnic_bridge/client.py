import json
import urllib.error
import urllib.request


class ApiError(Exception):
    def __init__(self, status: int, body: dict):
        super().__init__(f"HTTP {status}: {body.get('error') or body}")
        self.status, self.body = status, body


class Arnic:
    def __init__(self, server_url: str, api_key: str):
        self.base = server_url.rstrip("/")
        self.key = api_key

    def _call(self, method: str, path: str, payload: dict | None = None) -> dict:
        req = urllib.request.Request(
            self.base + path,
            method=method,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"Authorization": f"Bearer {self.key}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=90) as r:  # Render gratis tarda ~1 min en despertar
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            try:
                body = json.loads(e.read() or b"{}")
            except ValueError:
                body = {}
            raise ApiError(e.code, body) from None

    def add_expense(self, amount_minor: int, category: str, note: str, occurred_ms: int, account: str = "") -> dict:
        body = {"type": "expense", "amountMinor": amount_minor, "category": category, "note": note, "occurredAtMs": occurred_ms}
        if account:
            body["account"] = account
        try:
            return self._call("POST", "/v1/movements", body)
        except ApiError as e:
            if e.status == 422 and account and "cuenta" in str(e.body.get("error", "")).lower():
                body.pop("account")  # cuenta no reconocida: mejor en la predeterminada que perder el gasto
                return self._call("POST", "/v1/movements", body)
            raise

    def snapshot(self) -> dict:
        return self._call("GET", "/v1/sync?since=0")

    def push(self, rows: dict) -> dict:
        """POST /v1/sync: el mismo canal que usa el teléfono. El teléfono lo recibe en su próxima sincronización."""
        return self._call("POST", "/v1/sync", rows)
