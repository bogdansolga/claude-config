#!/usr/bin/env bash
# md2gdoc.sh — Insert Markdown content into a Google Doc with native formatting
# Uses gdocs.sh for API access.
#
# Usage:
#   md2gdoc.sh DOCUMENT_ID MARKDOWN_FILE
#
# Three-pass approach:
#   Pass 1: Insert all content as plain text (markdown syntax stripped, tables as tab-separated)
#   Pass 2: Read back doc JSON, find indices, apply formatting (headings, bold)
#   Pass 3: Run gdoc-tables.sh to convert tab-separated text to native Google Docs tables
#
# Supported formatting:
#   # H1 / ## H2 / ### H3  → Google Docs heading styles
#   **bold**                → bold text
#   --- (horizontal rule)   → horizontal rule (Unicode line)
#   | tables |              → Google Docs native tables
#   1. numbered lists       → numbered list bullets
#   - bullet lists          → bullet list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GDOCS="$SCRIPT_DIR/gdocs.sh"

DOC_ID="${1:?Usage: md2gdoc.sh DOCUMENT_ID MARKDOWN_FILE}"
MD_FILE="${2:?Usage: md2gdoc.sh DOCUMENT_ID MARKDOWN_FILE}"

# ── Pass 1: Build plain text and metadata ────────────────────────

# We need to:
# 1. Strip markdown syntax to get plain text
# 2. Record what formatting to apply (heading lines, bold ranges, table locations)
# Tables become placeholder text like "{{TABLE:N}}" that we'll replace with real tables in pass 2

# Use Python for the heavy lifting (parsing + JSON generation)
export _MD2GDOC_DOC_ID="$DOC_ID"
export _MD2GDOC_MD_FILE="$MD_FILE"
export _MD2GDOC_GDOCS="$GDOCS"

python3 << 'PYEOF'
import sys, re, json, subprocess, os

doc_id = os.environ["_MD2GDOC_DOC_ID"]
md_file = os.environ["_MD2GDOC_MD_FILE"]
gdocs = os.environ["_MD2GDOC_GDOCS"]

with open(md_file) as f:
    lines = f.read().rstrip('\n').split('\n')

# ── Parse markdown into segments ──────────────────────────────────

segments = []  # list of dicts: {type, text, ...}

i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()

    # Empty line
    if not stripped:
        segments.append({"type": "empty"})
        i += 1
        continue

    # Horizontal rule
    if stripped == '---':
        segments.append({"type": "hr"})
        i += 1
        continue

    # Headings
    if stripped.startswith('# ') and not stripped.startswith('## '):
        segments.append({"type": "heading", "level": 1, "text": stripped[2:]})
        i += 1
        continue
    if stripped.startswith('## ') and not stripped.startswith('### '):
        segments.append({"type": "heading", "level": 2, "text": stripped[3:]})
        i += 1
        continue
    if stripped.startswith('### '):
        segments.append({"type": "heading", "level": 3, "text": stripped[4:]})
        i += 1
        continue

    # Table
    if '|' in stripped and stripped.startswith('|'):
        table_rows = []
        while i < len(lines) and lines[i].strip().startswith('|'):
            row = lines[i].strip()
            cells = [c.strip() for c in row.split('|')[1:-1]]
            # Skip separator rows
            if not all(set(c) <= set('- :') for c in cells):
                table_rows.append(cells)
            i += 1
        segments.append({"type": "table", "rows": table_rows})
        continue

    # Numbered list item
    m = re.match(r'^(\d+)\.\s+(.+)', stripped)
    if m:
        items = []
        while i < len(lines):
            m2 = re.match(r'^\d+\.\s+(.+)', lines[i].strip())
            if not m2:
                break
            items.append(m2.group(1))
            i += 1
            # Consume continuation lines (indented sub-bullets under numbered items)
            while i < len(lines) and lines[i].startswith('   ') and lines[i].strip().startswith('- '):
                items[-1] += '\n' + lines[i].strip()[2:]  # append sub-item text
                i += 1
        segments.append({"type": "numbered_list", "items": items})
        continue

    # Bullet list item
    if stripped.startswith('- '):
        items = []
        while i < len(lines) and lines[i].strip().startswith('- '):
            items.append(lines[i].strip()[2:])
            i += 1
        segments.append({"type": "bullet_list", "items": items})
        continue

    # Regular paragraph
    segments.append({"type": "paragraph", "text": stripped})
    i += 1

# ── Build plain text content ─────────────────────────────────────

def strip_bold(text):
    """Remove ** markers from text"""
    return text.replace('**', '')

def strip_italic(text):
    """Remove * markers (single) from text — only standalone *word*"""
    return re.sub(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', r'\1', text)

def strip_emdash(text):
    """Replace em dash with hyphen"""
    return text.replace('\u2014', '-').replace('\u2013', '-')

def clean(text):
    return strip_emdash(strip_italic(strip_bold(text)))

plain_parts = []  # list of plain text strings
metadata = []     # parallel list: formatting info for each part

for seg in segments:
    t = seg["type"]
    if t == "empty":
        plain_parts.append("\n")
        metadata.append({"type": "empty"})
    elif t == "hr":
        plain_parts.append("━" * 50 + "\n")
        metadata.append({"type": "hr"})
    elif t == "heading":
        text = clean(seg["text"]) + "\n"
        plain_parts.append(text)
        metadata.append({"type": "heading", "level": seg["level"]})
    elif t == "paragraph":
        text = clean(seg["text"]) + "\n"
        plain_parts.append(text)
        metadata.append({"type": "paragraph", "raw": seg["text"]})
    elif t == "table":
        # Insert placeholder — we'll replace with real table later
        rows = seg["rows"]
        ncols = len(rows[0]) if rows else 0
        nrows = len(rows)
        # Build text representation for now
        table_text = ""
        for row in rows:
            table_text += "\t".join(clean(c) for c in row) + "\n"
        plain_parts.append(table_text)
        metadata.append({"type": "table", "rows": [[clean(c) for c in r] for r in rows],
                         "raw_rows": rows, "nrows": nrows, "ncols": ncols})
    elif t == "numbered_list":
        text = ""
        for item in seg["items"]:
            text += clean(item) + "\n"
        plain_parts.append(text)
        metadata.append({"type": "numbered_list", "items": seg["items"]})
    elif t == "bullet_list":
        text = ""
        for item in seg["items"]:
            text += clean(item) + "\n"
        plain_parts.append(text)
        metadata.append({"type": "bullet_list", "items": seg["items"]})

# Join all plain text
full_text = "".join(plain_parts)

# ── Pass 1: Insert plain text ────────────────────────────────────

print(f"Inserting {len(full_text)} chars of plain text...", file=sys.stderr)
result = subprocess.run([gdocs, "insert", doc_id, "1", full_text],
                       capture_output=True, text=True)
if result.returncode != 0:
    print(f"Insert failed: {result.stderr}", file=sys.stderr)
    sys.exit(1)

# ── Pass 2: Read back and build formatting requests ──────────────

print("Reading back document structure...", file=sys.stderr)
result = subprocess.run([gdocs, "read-json", doc_id], capture_output=True, text=True)
if result.returncode != 0:
    print(f"Read failed: {result.stderr}", file=sys.stderr)
    sys.exit(1)

doc_elements = json.loads(result.stdout)

# Build a list of paragraphs with their indices and text
paragraphs = []
for el in doc_elements:
    if "paragraph" in el:
        p = el["paragraph"]
        text = ""
        for elem in p.get("elements", []):
            tr = elem.get("textRun", {})
            text += tr.get("content", "")
        paragraphs.append({
            "startIndex": el["startIndex"],
            "endIndex": el["endIndex"],
            "text": text,
            "style": p.get("paragraphStyle", {}).get("namedStyleType", "")
        })

# Now match paragraphs to our metadata and build formatting requests
requests = []

# Track which paragraph index we're at
para_idx = 0

def find_paragraph(text_prefix, start_from=0):
    """Find the paragraph that starts with the given text"""
    for i in range(start_from, len(paragraphs)):
        p = paragraphs[i]
        if p["text"].strip().startswith(text_prefix[:30].strip()):
            return i, p
    return None, None

# Walk through metadata and match to paragraphs
current_para = 0
for seg_idx, (part, meta) in enumerate(zip(plain_parts, metadata)):
    t = meta["type"]

    if t == "empty":
        current_para += 1
        continue

    if t == "hr":
        # Find the HR paragraph and style it (smaller, gray)
        for pi in range(current_para, len(paragraphs)):
            if paragraphs[pi]["text"].strip().startswith("━"):
                requests.append({
                    "updateTextStyle": {
                        "range": {
                            "startIndex": paragraphs[pi]["startIndex"],
                            "endIndex": paragraphs[pi]["endIndex"] - 1
                        },
                        "textStyle": {
                            "fontSize": {"magnitude": 6, "unit": "PT"},
                            "foregroundColor": {"color": {"rgbColor": {"red": 0.7, "green": 0.7, "blue": 0.7}}}
                        },
                        "fields": "fontSize,foregroundColor"
                    }
                })
                current_para = pi + 1
                break
        continue

    if t == "heading":
        level = meta["level"]
        style_map = {1: "HEADING_1", 2: "HEADING_2", 3: "HEADING_3"}
        heading_text = clean(segments[seg_idx]["text"])[:30].strip()

        for pi in range(current_para, len(paragraphs)):
            if paragraphs[pi]["text"].strip().startswith(heading_text[:20]):
                requests.append({
                    "updateParagraphStyle": {
                        "range": {
                            "startIndex": paragraphs[pi]["startIndex"],
                            "endIndex": paragraphs[pi]["endIndex"]
                        },
                        "paragraphStyle": {"namedStyleType": style_map[level]},
                        "fields": "namedStyleType"
                    }
                })
                current_para = pi + 1
                break
        continue

    if t == "numbered_list":
        items = meta["items"]
        first_item = clean(items[0])[:25].strip()
        start_pi = None
        end_pi = None
        for pi in range(current_para, len(paragraphs)):
            if paragraphs[pi]["text"].strip().startswith(first_item[:20]):
                start_pi = pi
                end_pi = pi + len(items)
                break
        if start_pi is not None:
            requests.append({
                "createParagraphBullets": {
                    "range": {
                        "startIndex": paragraphs[start_pi]["startIndex"],
                        "endIndex": paragraphs[min(end_pi - 1, len(paragraphs) - 1)]["endIndex"]
                    },
                    "bulletPreset": "NUMBERED_DECIMAL_NESTED"
                }
            })
            current_para = end_pi
        continue

    if t == "bullet_list":
        items = meta["items"]
        first_item = clean(items[0])[:25].strip()
        start_pi = None
        end_pi = None
        for pi in range(current_para, len(paragraphs)):
            if paragraphs[pi]["text"].strip().startswith(first_item[:20]):
                start_pi = pi
                end_pi = pi + len(items)
                break
        if start_pi is not None:
            requests.append({
                "createParagraphBullets": {
                    "range": {
                        "startIndex": paragraphs[start_pi]["startIndex"],
                        "endIndex": paragraphs[min(end_pi - 1, len(paragraphs) - 1)]["endIndex"]
                    },
                    "bulletPreset": "BULLET_DISC_CIRCLE_SQUARE"
                }
            })
            current_para = end_pi
        continue

    if t == "table":
        # For table rows — bold the first row (header)
        raw_rows = meta["raw_rows"]
        if raw_rows:
            header_cells = [clean(c) for c in raw_rows[0]]
            first_cell = header_cells[0][:15].strip()
            for pi in range(current_para, len(paragraphs)):
                if paragraphs[pi]["text"].strip().startswith(first_cell):
                    # Bold entire header row paragraph
                    requests.append({
                        "updateTextStyle": {
                            "range": {
                                "startIndex": paragraphs[pi]["startIndex"],
                                "endIndex": paragraphs[pi]["endIndex"] - 1
                            },
                            "textStyle": {"bold": True},
                            "fields": "bold"
                        }
                    })
                    current_para = pi + len(raw_rows)
                    break
        continue

    if t == "paragraph":
        raw = meta.get("raw", "")
        # Find bold segments in the raw text
        bold_matches = list(re.finditer(r'\*\*(.+?)\*\*', raw))
        if bold_matches:
            # Find the matching paragraph
            clean_text = clean(raw)[:25].strip()
            for pi in range(current_para, len(paragraphs)):
                if paragraphs[pi]["text"].strip().startswith(clean_text[:20]):
                    # For each bold match, calculate position in clean text
                    p_start = paragraphs[pi]["startIndex"]
                    # Build clean text incrementally to track positions
                    clean_pos = 0
                    raw_pos = 0
                    raw_text = raw
                    for bm in bold_matches:
                        # Position of ** in raw text
                        bold_raw_start = bm.start()
                        bold_content = bm.group(1)
                        # Calculate clean position: chars before this bold, minus previous ** removed
                        text_before = re.sub(r'\*\*(.+?)\*\*', r'\1', raw[:bold_raw_start])
                        text_before = re.sub(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', r'\1', text_before)
                        clean_start = len(text_before)
                        clean_end = clean_start + len(strip_italic(bold_content))

                        requests.append({
                            "updateTextStyle": {
                                "range": {
                                    "startIndex": p_start + clean_start,
                                    "endIndex": p_start + clean_end
                                },
                                "textStyle": {"bold": True},
                                "fields": "bold"
                            }
                        })
                    current_para = pi + 1
                    break
        else:
            current_para += 1
        continue

    current_para += 1

# ── Pass 3: Apply formatting ─────────────────────────────────────

if requests:
    print(f"Applying {len(requests)} formatting requests...", file=sys.stderr)
    req_json = json.dumps(requests)
    result = subprocess.run([gdocs, "batch", doc_id, req_json],
                           capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Formatting failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    print(f"Done! Applied {len(requests)} formatting operations.", file=sys.stderr)
else:
    print("No formatting to apply.", file=sys.stderr)

print("Complete. Running table conversion...", file=sys.stderr)
PYEOF

# ── Pass 3: Convert tab-separated text to native tables ──────────
"$SCRIPT_DIR/gdoc-tables.sh" "$DOC_ID"
