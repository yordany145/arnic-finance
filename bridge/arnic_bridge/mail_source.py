import email
import email.policy
import email.utils
import html
import imaplib
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone


@dataclass
class Mail:
    message_id: str
    sender: str
    subject: str
    body: str
    date_ms: int


def _text(msg) -> str:
    part = msg.get_body(preferencelist=("plain", "html"))
    if part is None:
        return ""
    content = part.get_content()
    if part.get_content_type() == "text/html":
        content = re.sub(r"(?is)<(script|style).*?</\1>", " ", content)
        content = html.unescape(re.sub(r"<[^>]+>", " ", content))
    return re.sub(r"[ \t\r\f\v]+", " ", content).strip()


def from_bytes(raw: bytes) -> Mail:
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    when = email.utils.parsedate_to_datetime(msg["Date"]) if msg["Date"] else datetime.now(timezone.utc)
    return Mail(
        message_id=(msg["Message-ID"] or "").strip() or f"nomid-{hash(raw)}",
        sender=email.utils.parseaddr(msg["From"] or "")[1].lower(),
        subject=str(msg["Subject"] or ""),
        body=_text(msg),
        date_ms=int(when.timestamp() * 1000),
    )


def fetch_range(host: str, user: str, password: str, folder: str, senders: list, since: date, before: date | None = None):
    """Lee sin marcar como leído (BODY.PEEK). Solo correos de los remitentes del banco, desde `since` hasta antes de `before`."""
    criteria = ["SINCE", since.strftime("%d-%b-%Y")] + (["BEFORE", before.strftime("%d-%b-%Y")] if before else [])
    with imaplib.IMAP4_SSL(host) as imap:
        imap.login(user, password)
        imap.select(folder, readonly=True)
        ids = set()
        for s in senders:
            typ, data = imap.search(None, *criteria, "FROM", f'"{s}"')
            if typ == "OK":
                ids.update(data[0].split())
        for i in sorted(ids, key=int):
            typ, data = imap.fetch(i, "(BODY.PEEK[])")
            if typ == "OK" and data and isinstance(data[0], tuple):
                yield from_bytes(data[0][1])


def fetch_recent(host: str, user: str, password: str, folder: str, senders: list, days: int):
    return fetch_range(host, user, password, folder, senders, (datetime.now() - timedelta(days=days)).date())
