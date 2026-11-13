"""TECTICA login reports and public online-room directory.

Bind only to loopback; publish /tectica through Tailscale Funnel. The admin
key and database live in --data, outside the game and source repository.
Login reports reflect successful local authentication in official clients.
They are not proof of a globally verified account identity.
"""
import argparse
import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import urlsplit

from waitress import serve

TOKEN = re.compile(r"^[0-9a-f]{64}$")
VERSION = re.compile(r"^[0-9A-Za-z.+_-]{1,40}$")


class Community:
    def __init__(self, data):
        data = Path(data)
        data.mkdir(parents=True, exist_ok=True)
        key_file = data / "admin.key"
        if not key_file.exists():
            key_file.write_text(secrets.token_hex(32), encoding="utf-8")
        self.admin_key = key_file.read_text(encoding="utf-8").strip()
        self.database = str(data / "community.sqlite3")
        self.lock = threading.Lock()
        self.rates = {}
        with self.connect() as db:
            db.executescript("""
                PRAGMA max_page_count=65536;
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS logins (
                    installation TEXT NOT NULL, event_id TEXT NOT NULL,
                    player TEXT NOT NULL, happened REAL NOT NULL,
                    received REAL NOT NULL, version TEXT NOT NULL,
                    PRIMARY KEY (installation, event_id)
                );
                CREATE INDEX IF NOT EXISTS login_received ON logins(received);
                CREATE TABLE IF NOT EXISTS rooms (
                    installation TEXT PRIMARY KEY, name TEXT NOT NULL,
                    address TEXT NOT NULL, mode TEXT NOT NULL, map TEXT NOT NULL,
                    players INTEGER NOT NULL, version TEXT NOT NULL, seen REAL NOT NULL
                );
            """)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()

    def allowed(self, identity, limit=60):
        now = time.monotonic()
        with self.lock:
            self.rates = {k: v for k, v in self.rates.items() if now - v[0] < 60}
            start, count = self.rates.get(identity, (now, 0))
            if count >= limit:
                return False
            self.rates[identity] = (start, count + 1)
        return True

    def __call__(self, env, start_response):
        try:
            status, body = self.route(env)
        except (ValueError, TypeError, KeyError, UnicodeError, json.JSONDecodeError):
            status, body = "400 Bad Request", {"error": "Invalid request"}
        except sqlite3.Error:
            status, body = "503 Service Unavailable", {"error": "Storage temporarily unavailable"}
        encoded = json.dumps(body, ensure_ascii=True).encode()
        start_response(status, [
            ("Content-Type", "application/json"),
            ("Content-Length", str(len(encoded))),
            ("Cache-Control", "no-store"),
            ("X-Content-Type-Options", "nosniff"),
        ])
        return [encoded]

    def route(self, env):
        path = env.get("PATH_INFO", "").removeprefix("/tectica").rstrip("/")
        method = env["REQUEST_METHOD"]
        now = time.time()
        if method == "GET" and path == "/health":
            return "200 OK", {"ok": True}
        if method == "GET" and path == "/rooms":
            with self.connect() as db:
                rows = db.execute(
                    "SELECT installation,name,address,mode,map,players,version FROM rooms "
                    "WHERE seen>? ORDER BY seen DESC LIMIT 100", (now - 45,)
                ).fetchall()
            keys = ["id", "name", "address", "mode", "map", "players", "version"]
            return "200 OK", {"rooms": [dict(zip(keys, r)) for r in rows]}
        bearer = env.get("HTTP_AUTHORIZATION", "").removeprefix("Bearer ")
        if method == "GET" and path == "/admin/logins":
            if not hmac.compare_digest(bearer, self.admin_key):
                return "403 Forbidden", {"error": "Owner access required"}
            with self.connect() as db:
                rows = db.execute(
                    "SELECT installation,lower(player),MAX(player),MIN(happened),MAX(happened),"
                    "COUNT(*) FROM logins GROUP BY installation,lower(player) "
                    "ORDER BY MAX(happened) DESC LIMIT 1000"
                ).fetchall()
                events = db.execute(
                    "SELECT player,happened,version,installation FROM logins ORDER BY happened DESC LIMIT 200"
                ).fetchall()
                total = db.execute("SELECT COUNT(*) FROM logins").fetchone()[0]
                active = db.execute(
                    "SELECT COUNT(*) FROM (SELECT installation,lower(player) FROM logins "
                    "WHERE happened>? GROUP BY installation,lower(player))", (now - 86400,)
                ).fetchone()[0]
            return "200 OK", {
                "rows": [{"id": r[0] + ":" + r[1], "name": r[2], "created": r[3],
                          "last": r[4], "logins": r[5], "device": r[0][:8]} for r in rows],
                "events": [{"user": r[0], "t": r[1], "version": r[2], "device": r[3][:8],
                            "event": "sign_in"} for r in events],
                "total": total, "active": active,
            }
        if method not in ("POST", "DELETE") or path not in ("/logins", "/room"):
            return "404 Not Found", {"error": "Unknown endpoint"}
        if not TOKEN.fullmatch(bearer):
            return "401 Unauthorized", {"error": "Installation token required"}
        identity = hashlib.sha256(bearer.encode()).hexdigest()
        if not self.allowed("all-writes", 600) or not self.allowed(identity):
            return "429 Too Many Requests", {"error": "Retry later"}
        if method == "DELETE" and path == "/room":
            with self.connect() as db:
                db.execute("DELETE FROM rooms WHERE installation=?", (identity,))
            return "200 OK", {"ok": True}
        if method != "POST":
            return "405 Method Not Allowed", {"error": "POST required"}
        length = int(env.get("CONTENT_LENGTH") or 0)
        if length < 1 or length > 16384:
            return "413 Payload Too Large", {"error": "Invalid body size"}
        body = json.loads(env["wsgi.input"].read(length))
        if not isinstance(body, dict):
            raise ValueError()
        if path == "/logins":
            events = body["events"]
            if not isinstance(events, list) or not 1 <= len(events) <= 32:
                raise ValueError()
            validated = []
            for e in events:
                player, event_id, version = e["player"], e["id"], e["version"]
                if (not isinstance(player, str) or not 3 <= len(player) <= 16
                        or not all(c.isalnum() or c in "_-" for c in player)
                        or not TOKEN.fullmatch(event_id) or not VERSION.fullmatch(version)):
                    raise ValueError()
                happened = float(e["time"])
                if not 0 < happened <= now + 300:
                    happened = now
                validated.append((identity, event_id, player, happened, now, version))
            with self.connect() as db:
                db.executemany("INSERT OR IGNORE INTO logins VALUES (?,?,?,?,?,?)", validated)
            return "200 OK", {"ok": True}
        name, address = body["name"], body["address"]
        endpoint = urlsplit(address)
        if (not isinstance(name, str) or not 1 <= len(name) <= 40
                or any(ord(c) < 32 for c in name)
                or endpoint.scheme != "wss" or not (endpoint.hostname or "").endswith(".ts.net")
                or endpoint.port != 10000 or endpoint.username or endpoint.password
                or endpoint.path not in ("", "/") or endpoint.query or endpoint.fragment
                or not VERSION.fullmatch(body["version"])
                or body["mode"] not in ("coop", "pvp")
                or body["map"] not in ("forest", "town")
                or type(body["players"]) is not int or not 1 <= body["players"] <= 8):
            raise ValueError()
        with self.connect() as db:
            db.execute("DELETE FROM rooms WHERE seen<?", (now - 45,))
            db.execute(
                "INSERT INTO rooms VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(installation) "
                "DO UPDATE SET name=excluded.name,address=excluded.address,mode=excluded.mode,"
                "map=excluded.map,players=excluded.players,version=excluded.version,seen=excluded.seen",
                (identity, name, address, body["mode"], body["map"], body["players"], body["version"], now),
            )
        return "200 OK", {"ok": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True)
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    serve(Community(args.data), host="127.0.0.1", port=args.port, threads=4,
          max_request_body_size=16384, channel_timeout=15, connection_limit=64)
