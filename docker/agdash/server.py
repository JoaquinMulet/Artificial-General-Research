#!/usr/bin/env python3
"""agdash - zero-dependency dashboard server for one AGR campaign.

Serves from /data (the campaign repo volume, read-only):
  GET /                  dashboard.html if the campaign generated one, else a
                         minimal self-generated status page
  GET /api/state         agr_logs/state.json
  GET /api/results?n=50  last N rows of results.tsv (raw text)
  GET /api/heartbeat     heartbeat age in seconds + container clock

ASCII-only output (no campaign content is interpreted here).
"""
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA = "/data"
PORT = int(os.environ.get("AGR_DASH_PORT", "8080"))


def read(path, binary=False):
    mode = "rb" if binary else "r"
    try:
        with open(path, mode, encoding=None if binary else "utf-8",
                  errors="replace") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return None


def heartbeat_age():
    hb = os.path.join(DATA, "agr_logs", "heartbeat")
    try:
        return int(time.time() - os.path.getmtime(hb))
    except OSError:
        return None


def minimal_page():
    age = heartbeat_age()
    state = read(os.path.join(DATA, "agr_logs", "state.json"))
    rows = read(os.path.join(DATA, "results.tsv"))
    state_txt = state or "{ }"
    if rows:
        rows_txt = "\n".join(rows.strip().splitlines()[-10:])
    else:
        rows_txt = "(no results.tsv yet)"
    hb = "fresh" if age is not None and age < 1500 else ("stale" if age is not None else "missing")
    return f"""<!doctype html><html><head><meta charset="utf-8">
<title>AGR Dashboard</title>
<style>body{{font-family:monospace;margin:2em}}pre{{background:#f5f5f5;padding:1em}}</style>
<meta http-equiv="refresh" content="10"></head><body>
<h1>AGR Dashboard (minimal - no dashboard.html in campaign)</h1>
<p>heartbeat: {hb} (age {age}s) | auto-refresh 10s</p>
<h2>state.json</h2><pre>{state_txt}</pre>
<h2>results.tsv (last 10)</h2><pre>{rows_txt}</pre>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/dashboard.html"):
            page = read(os.path.join(DATA, "dashboard.html"))
            if page is not None:
                self._send(200, page.encode("utf-8"), "text/html; charset=utf-8")
            else:
                self._send(200, minimal_page().encode("utf-8"), "text/html; charset=utf-8")
        elif self.path == "/api/state":
            body = read(os.path.join(DATA, "agr_logs", "state.json")) or "{}"
            self._send(200, body.encode("utf-8"), "application/json")
        elif self.path.startswith("/api/results"):
            n = 50
            m = re.search(r"[?&]n=(\d+)", self.path)
            if m:
                n = min(int(m.group(1)), 1000)
            rows = read(os.path.join(DATA, "results.tsv"))
            if rows is None:
                self._send(404, b"no results.tsv", "text/plain")
                return
            tail = "\n".join(rows.strip().splitlines()[-n:]) + "\n"
            self._send(200, tail.encode("utf-8"), "text/plain; charset=utf-8")
        elif self.path == "/api/heartbeat":
            age = heartbeat_age()
            self._send(200, json.dumps({"age_s": age,
                                        "status": "fresh" if age is not None and age < 1500
                                                  else ("stale" if age is not None else "missing")}
                                       ).encode("utf-8"), "application/json")
        else:
            self._send(404, b"not found", "text/plain")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
