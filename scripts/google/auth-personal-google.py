#!/usr/bin/env python3
"""Re-authenticate a Google OAuth token for a chosen account via the installed-app
loopback flow. Writes a token.json compatible with gdocs.sh / gslides.sh / deck-lib.sh
(fields: token, refresh_token, client_id, client_secret, expiry).

Client source, in priority order:
  1. CLIENT_SECRET_FILE  — a Google-downloaded OAuth client JSON ({"installed":{...}} or {"web":{...}}).
                           Preferred: your own Desktop-app client with a Published consent screen
                           (durable refresh tokens).
  2. CLIENT_FROM         — borrow id+secret from an existing token.json
                           (default ~/.config/gog-scripts/token.json; Testing-mode → tokens expire ~7 days).

Log in as the account you want this token to represent.

Usage:
  python3 auth-personal-google.py
Env overrides:
  CLIENT_SECRET_FILE  path to a downloaded client_secret_*.json (takes priority)
  CLIENT_FROM         token.json to borrow the OAuth client id+secret from
  OUT                 where to write the new token (default: ~/.config/gdocs-personal/token.json)
  PORT                loopback port (default: 8765)
  SCOPES              space-separated scopes (default: drive + spreadsheets — drive covers Docs+Slides)
"""
import http.server, json, os, socket, sys, threading, time, urllib.parse, urllib.request
from datetime import datetime, timezone, timedelta

HOME = os.path.expanduser("~")
CLIENT_SECRET_FILE = os.environ.get("CLIENT_SECRET_FILE", "")
CLIENT_FROM = os.environ.get("CLIENT_FROM", f"{HOME}/.config/gog-scripts/token.json")
OUT = os.environ.get("OUT", f"{HOME}/.config/gdocs-personal/token.json")
PORT = int(os.environ.get("PORT", "8765"))
SCOPES = os.environ.get(
    "SCOPES",
    "https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/spreadsheets",
)
REDIRECT = f"http://localhost:{PORT}/"
AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN = "https://oauth2.googleapis.com/token"

if CLIENT_SECRET_FILE:
    with open(CLIENT_SECRET_FILE) as f:
        cs = json.load(f)
    src = cs.get("installed") or cs.get("web") or cs
    print(f"(using client from {CLIENT_SECRET_FILE})", flush=True)
else:
    with open(CLIENT_FROM) as f:
        src = json.load(f)
    print(f"(borrowing client from {CLIENT_FROM})", flush=True)
CLIENT_ID = src["client_id"]
CLIENT_SECRET = src["client_secret"]

params = {
    "client_id": CLIENT_ID,
    "redirect_uri": REDIRECT,
    "response_type": "code",
    "scope": SCOPES,
    "access_type": "offline",
    "prompt": "consent",
    "include_granted_scopes": "true",
}
auth_url = AUTH + "?" + urllib.parse.urlencode(params)

# Fail fast if the port is busy.
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(("127.0.0.1", PORT))
finally:
    s.close()

print("OPEN_THIS_URL>>>", flush=True)
print(auth_url, flush=True)
print("<<<", flush=True)
print(f"(listening on {REDIRECT} — log in as the account you want this token for)", flush=True)

result = {}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        q = urllib.parse.urlparse(self.path).query
        qs = urllib.parse.parse_qs(q)
        if "code" in qs:
            result["code"] = qs["code"][0]
            body = b"<h2>Authorized. You can close this tab and return to the terminal.</h2>"
        elif "error" in qs:
            result["error"] = qs["error"][0]
            body = ("<h2>Auth error: %s</h2>" % qs["error"][0]).encode()
        else:
            body = b"<h2>Waiting for the OAuth redirect...</h2>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


httpd = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
# Wait up to 5 minutes for the user to complete the browser login.
deadline = time.time() + 300
while not result and time.time() < deadline:
    httpd.timeout = 2
    httpd.handle_request()

if "code" not in result:
    print("ERROR: no authorization code received (timeout or error: %s)" % result.get("error"), file=sys.stderr)
    sys.exit(1)

data = urllib.parse.urlencode({
    "code": result["code"],
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,
    "redirect_uri": REDIRECT,
    "grant_type": "authorization_code",
}).encode()
try:
    with urllib.request.urlopen(urllib.request.Request(TOKEN, data=data)) as r:
        tok = json.load(r)
except urllib.error.HTTPError as e:
    print("ERROR: token exchange failed:", e.read().decode(), file=sys.stderr)
    sys.exit(1)

expiry = (datetime.now(timezone.utc) + timedelta(seconds=tok.get("expires_in", 3600))).strftime("%Y-%m-%dT%H:%M:%SZ")
out = {
    "token": tok["access_token"],
    "refresh_token": tok.get("refresh_token", src.get("refresh_token", "")),
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,
    "token_uri": TOKEN,
    "scopes": SCOPES.split(),
    "expiry": expiry,
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(out, f, indent=2)
os.chmod(OUT, 0o600)

# Confirm the account.
try:
    req = urllib.request.Request(
        "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)",
        headers={"Authorization": "Bearer " + tok["access_token"]},
    )
    with urllib.request.urlopen(req) as r:
        who = json.load(r)["user"]["emailAddress"]
except Exception as e:
    who = "(could not fetch: %s)" % e

print("WROTE_TOKEN>>>", OUT, flush=True)
print("ACCOUNT>>>", who, flush=True)
