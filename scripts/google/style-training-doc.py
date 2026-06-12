#!/usr/bin/env python3
"""Style a training-overview Google Doc to match the house reference look:

  - Title line        -> centered, bold, 14pt
  - Subtitle line     -> centered, grey (0.6), 12pt   (split off the title if merged)
  - Section headers   -> bold, 13pt, blue (#0000ff), first-line indent 36pt, spaceBelow 10
  - Day headers       -> same as section headers
  - Body & bullets    -> 12pt spaceAbove/below
  - Line spacing 1.5 (150) everywhere
  - Markdown artifacts stripped: literal ** around headers, --- rules
  - Blank-line runs collapsed to a single blank (one blank line between blocks)

The reference uses NO heading styles — everything is bold-sized NORMAL_TEXT — so we mirror that.
Idempotent / re-runnable. Preserves hyperlinks (operates by index, never re-inserts text).

Usage:  python3 style-training-doc.py [DOC_ID]
Env:
  TOKEN_PATH          token.json (default ~/.config/gdocs-personal/token.json)
  DOC_TITLE_PREFIX    text the title line starts with (default "Kubernetes training")
  DOC_SECTION_HEADERS JSON array of section-header strings (override per course)
  DOC_DAY_REGEX       regex matching day/module headers (override per course)
"""
import json, os, re, sys, urllib.parse, urllib.request, urllib.error
from datetime import datetime, timezone, timedelta

TOKEN_PATH = os.environ.get("TOKEN_PATH", os.path.expanduser("~/.config/gdocs-personal/token.json"))
DOC = sys.argv[1] if len(sys.argv) > 1 else "1VrPEJlcsEoA7UkDAkxWtFlHBFpZ0nonFAhSqQMKsuGM"
BASE = f"https://docs.googleapis.com/v1/documents/{DOC}"

# ── per-course config (override via env to reuse on other training docs) ──
TITLE_PREFIX = os.environ.get("DOC_TITLE_PREFIX", "Kubernetes training")
SECTION_HEADERS = set(json.loads(os.environ["DOC_SECTION_HEADERS"])) if os.environ.get("DOC_SECTION_HEADERS") else {
    "Training description", "Training objectives",
    "Training duration, days and sessions scheduling",
    "Targeted audience", "Prerequisites", "Presented topics", "Additional notes",
}
DAY_RE = re.compile(os.environ.get("DOC_DAY_REGEX", r"^(Day [123]:|Advanced Modules \(optional 4th day\))"))

PT = lambda n: {"magnitude": n, "unit": "PT"}
BLUE = {"color": {"rgbColor": {"blue": 1.0}}}
GREY = {"color": {"rgbColor": {"red": 0.6, "green": 0.6, "blue": 0.6}}}
LINE = 150


# ── token + api ──────────────────────────────────────────────────
def get_token():
    with open(TOKEN_PATH) as f:
        t = json.load(f)
    exp = t.get("expiry", "1970-01-01T00:00:00Z").replace("Z", "+00:00")
    if datetime.now(timezone.utc) < datetime.fromisoformat(exp):
        return t["token"]
    data = urllib.parse.urlencode({
        "client_id": t["client_id"], "client_secret": t["client_secret"],
        "refresh_token": t["refresh_token"], "grant_type": "refresh_token",
    }).encode()
    with urllib.request.urlopen("https://oauth2.googleapis.com/token", data=data) as r:
        nt = json.load(r)
    t["token"] = nt["access_token"]
    t["expiry"] = (datetime.now(timezone.utc) + timedelta(seconds=nt.get("expires_in", 3600))).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(TOKEN_PATH, "w") as f:
        json.dump(t, f, indent=2)
    return t["token"]


def api(method, url, payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Authorization": "Bearer " + get_token(),
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print("API ERROR", e.code, e.read().decode()[:500], file=sys.stderr)
        sys.exit(1)


def get_doc():
    return api("GET", BASE)


def batch(requests):
    if requests:
        api("POST", BASE + ":batchUpdate", {"requests": requests})


def paras(doc):
    for el in doc["body"]["content"]:
        if "paragraph" in el:
            yield el


def text_of(el):
    return "".join(e.get("textRun", {}).get("content", "") for e in el["paragraph"].get("elements", []))


def star_ranges(el):
    out = []
    for e in el["paragraph"].get("elements", []):
        tr = e.get("textRun")
        if not tr:
            continue
        base = e["startIndex"]
        for i, ch in enumerate(tr.get("content", "")):
            if ch == "*":
                out.append((base + i, base + i + 1))
    return out


# ── pass 1: delete artifacts (--- rules + literal ** ) ───────────
doc = get_doc()
dels = []
for el in paras(doc):
    txt = text_of(el)
    if txt.replace("*", "").strip() == "---":
        dels.append((el["startIndex"], el["endIndex"]))
    elif "*" in txt:
        dels.extend(star_ranges(el))
dels.sort(key=lambda r: r[0], reverse=True)
batch([{"deleteContentRange": {"range": {"startIndex": s, "endIndex": e}}} for s, e in dels])
print(f"pass 1: removed {len(dels)} artifact range(s)")

# ── pass 1.5: collapse runs of >=2 blank paragraphs to one (loop to convergence) ──
iters = 0
for _ in range(8):
    doc = get_doc()
    starts, run_start, run_len = [], None, 0
    for el in paras(doc):
        if text_of(el).strip() == "":
            if run_len == 0:
                run_start = el["startIndex"]
            run_len += 1
        else:
            if run_len >= 2:
                starts.append(run_start)   # delete ONE blank from this run
            run_len = 0
    if run_len >= 2:
        starts.append(run_start)
    if not starts:
        break
    starts.sort(reverse=True)
    batch([{"deleteContentRange": {"range": {"startIndex": s, "endIndex": s + 1}}} for s in starts])
    iters += 1
print(f"pass 1.5: collapsed blank runs to one line each ({iters} iteration(s))")

# ── pass 2: split a merged "Title-- subtitle" line ───────────────
doc = get_doc()
for el in paras(doc):
    txt = text_of(el)
    if txt.startswith(TITLE_PREFIX):
        body = txt.rstrip("\n")
        if body != TITLE_PREFIX and "--" in body:
            off = body.index("--")
            batch([{"insertText": {"location": {"index": el["startIndex"] + off}, "text": "\n"}}])
            print("pass 2: split title / subtitle")
        else:
            print("pass 2: title already separate")
        break

# ── pass 3: full styling ─────────────────────────────────────────
doc = get_doc()
reqs = []


def txt_style(el, size=None, bold=None, color=None):
    s, e = el["startIndex"], max(el["startIndex"] + 1, el["endIndex"] - 1)
    ts, fields = {}, []
    if bold is not None:
        ts["bold"] = bold; fields.append("bold")
    if size is not None:
        ts["fontSize"] = PT(size); fields.append("fontSize")
    if color is not None:
        ts["foregroundColor"] = color; fields.append("foregroundColor")
    if fields:
        reqs.append({"updateTextStyle": {"range": {"startIndex": s, "endIndex": e},
                                          "textStyle": ts, "fields": ",".join(fields)}})


def par_style(el, align=None, above=None, below=None, first=None, line=None):
    s, e = el["startIndex"], max(el["startIndex"] + 1, el["endIndex"] - 1)
    ps, fields = {}, []
    if align is not None:
        ps["alignment"] = align; fields.append("alignment")
    if above is not None:
        ps["spaceAbove"] = PT(above); fields.append("spaceAbove")
    if below is not None:
        ps["spaceBelow"] = PT(below); fields.append("spaceBelow")
    if first is not None:
        ps["indentFirstLine"] = PT(first); fields.append("indentFirstLine")
    if line is not None:
        ps["lineSpacing"] = line; fields.append("lineSpacing")
    if fields:
        reqs.append({"updateParagraphStyle": {"range": {"startIndex": s, "endIndex": e},
                                               "paragraphStyle": ps, "fields": ",".join(fields)}})


seen_title = False
for el in paras(doc):
    t = text_of(el).rstrip("\n")
    key = t.strip()
    if not key:
        continue
    if not seen_title and t.startswith(TITLE_PREFIX):
        txt_style(el, 14, True); par_style(el, align="CENTER", above=10, line=LINE); seen_title = True
    elif t.startswith("--") and "objectives" in t:
        txt_style(el, 12, False, GREY); par_style(el, align="CENTER", line=LINE)
    elif key in SECTION_HEADERS or DAY_RE.match(key):
        txt_style(el, 13, True, BLUE); par_style(el, first=36, below=10, line=LINE)
    else:
        par_style(el, above=12, below=12, line=LINE)
batch(reqs)
print(f"pass 3: applied {len(reqs)} style request(s) "
      "(centered title/subtitle, blue indented headers, 1.5 line, 12pt spacing)")
print("done.")
