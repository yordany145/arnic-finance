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
