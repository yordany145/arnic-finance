import sqlite3


class State:
    """Marcas de lo ya procesado/avisado, para que repetir una corrida no duplique nada."""

    def __init__(self, path: str):
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS seen (key TEXT PRIMARY KEY, at INTEGER DEFAULT (strftime('%s','now')))")

    def has(self, key: str) -> bool:
        return self.db.execute("SELECT 1 FROM seen WHERE key=?", (key,)).fetchone() is not None

    def add(self, key: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO seen(key) VALUES (?)", (key,))
        self.db.commit()
