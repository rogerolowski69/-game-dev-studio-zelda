"""Minimal stand-in for bridge-service used to drive the Godot wallet flows."""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE, LOG = sys.argv[1], sys.argv[2]  # MODE: ownership_502 | indexer_lag
state = {"mint_requested": False, "hits": {}}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        key = self.command + " " + self.path.split("?")[0]
        state["hits"][key] = state["hits"].get(key, 0) + 1
        with open(LOG, "w") as f:
            json.dump(state["hits"], f)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/connect":
            self._send(200, {"alreadyConnected": False, "universalLink": "tc://mock", "walletName": "Mock"})
        elif self.path == "/mint":
            state["mint_requested"] = True
            self._send(200, {"collection": "zoneAccessPass", "status": "pending"})

    def do_GET(self):
        if self.path.startswith("/status"):
            # Bridge marks the tx "confirmed" as soon as the wallet returns a signed BoC.
            tx = {"collection": "zoneAccessPass", "status": "confirmed", "error": None} if state["mint_requested"] else None
            self._send(200, {"status": "connected", "address": "0:abc", "universalLink": None, "error": None, "tx": tx})
        elif self.path.startswith("/ownership"):
            if MODE == "ownership_502":
                self._send(502, {"error": "tonapi /v2/accounts/0:abc/nfts returned 429"})
            else:  # indexer has not seen the new NFT yet
                self._send(200, {"accessPass": False, "sword": {"owned": False, "attackDamage": None}})


ThreadingHTTPServer(("127.0.0.1", 4000), Handler).serve_forever()
