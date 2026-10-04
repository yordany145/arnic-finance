import json
import urllib.parse
import urllib.request


class Telegram:
    def __init__(self, config_path: str):
        c = json.load(open(config_path))
        self.token, self.chat_id = c["telegram_token"], c["authorized_telegram_id"]

    def send(self, text: str) -> None:
        data = urllib.parse.urlencode({"chat_id": self.chat_id, "text": text}).encode()
        urllib.request.urlopen(f"https://api.telegram.org/bot{self.token}/sendMessage", data=data, timeout=30).read()

    def send_document(self, path: str, caption: str = "") -> None:
        """Envía un archivo (p. ej. el Excel mensual). Multipart armado a mano para no depender de librerías."""
        import mimetypes
        import os
        import uuid
        boundary = uuid.uuid4().hex
        parts = []
        for name, value in (("chat_id", str(self.chat_id)), ("caption", caption)):
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
        mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="document"; filename="{os.path.basename(path)}"\r\nContent-Type: {mime}\r\n\r\n'.encode())
        parts.append(open(path, "rb").read())
        parts.append(f"\r\n--{boundary}--\r\n".encode())
        req = urllib.request.Request(f"https://api.telegram.org/bot{self.token}/sendDocument", data=b"".join(parts),
                                     headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
        urllib.request.urlopen(req, timeout=60).read()
