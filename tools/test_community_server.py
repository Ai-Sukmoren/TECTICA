import io
import json
import tempfile
import time
import unittest

from community_server import Community


class CommunityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = Community(self.directory.name)
        self.token = "a" * 64

    def tearDown(self):
        self.directory.cleanup()

    def request(self, method, path, body=None, token="", sender=""):
        raw = json.dumps(body).encode() if body is not None else b""
        env = {"REQUEST_METHOD": method, "PATH_INFO": path,
               "CONTENT_LENGTH": str(len(raw)), "wsgi.input": io.BytesIO(raw),
               "HTTP_AUTHORIZATION": "Bearer " + token}
        if sender:
            env["HTTP_X_FORWARDED_FOR"] = sender
        status = []
        response = self.app(env, lambda value, _headers: status.append(value))
        return int(status[0].split()[0]), json.loads(b"".join(response))

    def event(self):
        return {"id": "b" * 64, "player": "TestPlayer", "time": time.time(), "version": "1.14.0-beta"}

    def test_owner_only_and_retry_deduplication(self):
        payload = {"events": [self.event()]}
        self.assertEqual(self.request("POST", "/logins", payload)[0], 401)
        for _ in range(2):
            self.assertEqual(self.request("POST", "/logins", payload, self.token)[0], 200)
        self.assertEqual(self.request("GET", "/admin/logins")[0], 403)
        self.assertEqual(self.request("GET", "/admin/logins", token=self.token)[0], 403)
        code, result = self.request("GET", "/admin/logins", token=self.app.admin_key)
        self.assertEqual(code, 200)
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["active"], 1)
        self.assertEqual(result["rows"][0]["name"], "TestPlayer")

    def test_invalid_batch_is_atomic_and_devices_are_distinct(self):
        invalid = self.event()
        invalid["player"] = "bad\nname"
        self.assertEqual(self.request("POST", "/logins", {"events": [self.event(), invalid]}, self.token)[0], 400)
        self.assertEqual(self.request("GET", "/admin/logins", token=self.app.admin_key)[1]["total"], 0)
        for token in [self.token, "c" * 64]:
            self.request("POST", "/logins", {"events": [self.event()]}, token)
        self.assertEqual(len(self.request("GET", "/admin/logins", token=self.app.admin_key)[1]["rows"]), 2)

    def test_new_maps_and_direct_rooms(self):
        room = {"name": "Test Room", "address": "wss://host.example.ts.net:10000",
                "mode": "pvp", "map": "warehouse", "players": 1, "version": "1.37.0-beta"}
        self.assertEqual(self.request("POST", "/room", room, self.token)[0], 200)
        direct = dict(room, address="8.8.8.8:7777")
        # direct rooms: only the sender's own public address
        self.assertEqual(self.request("POST", "/room", direct, self.token)[0], 400)
        self.assertEqual(self.request("POST", "/room", direct, self.token, sender="1.1.1.1")[0], 400)
        self.assertEqual(self.request("POST", "/room", direct, self.token, sender="8.8.8.8")[0], 200)
        private = dict(room, address="192.168.1.5:7777")
        self.assertEqual(self.request("POST", "/room", private, self.token, sender="192.168.1.5")[0], 400)
        self.assertEqual(self.request("GET", "/rooms")[1]["rooms"][0]["address"], "8.8.8.8:7777")

    def test_live_rooms_expire_and_only_owner_can_remove(self):
        room = {"name": "Test Room", "address": "wss://host.example.ts.net:10000",
                "mode": "coop", "map": "forest", "players": 1, "version": "1.14.0-beta"}
        self.assertEqual(self.request("POST", "/room", room, self.token)[0], 200)
        self.assertEqual(len(self.request("GET", "/rooms")[1]["rooms"]), 1)
        self.request("DELETE", "/room", token="c" * 64)
        self.assertEqual(len(self.request("GET", "/rooms")[1]["rooms"]), 1)
        with self.app.connect() as db:
            db.execute("UPDATE rooms SET seen=?", (time.time() - 46,))
        self.assertEqual(self.request("GET", "/rooms")[1]["rooms"], [])
        self.request("POST", "/room", room, self.token)
        self.request("DELETE", "/room", token=self.token)
        self.assertEqual(self.request("GET", "/rooms")[1]["rooms"], [])
        room["address"] = "ws://127.0.0.1:7778"
        self.assertEqual(self.request("POST", "/room", room, self.token)[0], 400)


if __name__ == "__main__":
    unittest.main()
