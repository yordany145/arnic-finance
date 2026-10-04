import sqlite3


class State:
    """Marcas de lo ya procesado/avisado, para que repetir una corrida no duplique nada."""

    def __init__(self, path: str):
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS learned (merchant TEXT PRIMARY KEY, category TEXT NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS seen (key TEXT PRIMARY KEY, at INTEGER DEFAULT (strftime('%s','now')))")

    def has(self, key: str) -> bool:
        return self.db.execute("SELECT 1 FROM seen WHERE key=?", (key,)).fetchone() is not None

    def add(self, key: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO seen(key) VALUES (?)", (key,))
        self.db.commit()

    def learned(self) -> dict:
        return dict(self.db.execute("SELECT merchant, category FROM learned").fetchall())

    def learn(self, merchant: str, category: str) -> None:
        self.db.execute("INSERT INTO learned(merchant, category) VALUES (?, ?) ON CONFLICT(merchant) DO UPDATE SET category=excluded.category", (merchant, category))
        self.db.commit()

    def forget(self, merchant: str) -> None:
        self.db.execute("DELETE FROM learned WHERE merchant=?", (merchant,))
        self.db.commit()
