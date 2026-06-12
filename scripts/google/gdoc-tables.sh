#!/usr/bin/env bash
# gdoc-tables.sh - Convert tab-separated text lines in a Google Doc to native tables
#
# Usage:
#   gdoc-tables.sh DOCUMENT_ID [--from-index N] [--to-index N]
#
# Finds all consecutive paragraph groups that contain tabs (\t),
# treats each group as a table, and replaces the text with a native Google Docs table.
# Header row (first row) is bolded automatically.
#
# Options:
#   --from-index N   Only convert tab-separated groups whose paragraphs start at >= N
#                    (use after appending content; pass the doc end-index captured BEFORE
#                    the append to convert only the newly added groups).
#   --to-index N     Only convert tab-separated groups whose paragraphs end at <= N.
#
# Table cell index formula (for an empty table inserted at position P):
#   S = P + 1  (table start)
#   Cell(r, c) paragraph index = S + 3 + r * (1 + 2*C) + c * 2
#   where R = rows, C = columns
#   Fill cells in REVERSE order to avoid index shifts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GDOCS="$SCRIPT_DIR/gdocs.sh"

DOC_ID="${1:?Usage: gdoc-tables.sh DOCUMENT_ID [--from-index N] [--to-index N]}"
shift

FROM_INDEX=0
TO_INDEX=0  # 0 means "no upper bound"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-index)
      FROM_INDEX="${2:?--from-index requires a numeric value}"
      shift 2
      ;;
    --to-index)
      TO_INDEX="${2:?--to-index requires a numeric value}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: gdoc-tables.sh DOCUMENT_ID [--from-index N] [--to-index N]" >&2
      exit 1
      ;;
  esac
done

export _GDTBL_DOC_ID="$DOC_ID"
export _GDTBL_GDOCS="$GDOCS"
export _GDTBL_FROM_INDEX="$FROM_INDEX"
export _GDTBL_TO_INDEX="$TO_INDEX"

python3 << 'PYEOF'
import os, json, subprocess, sys

doc_id = os.environ["_GDTBL_DOC_ID"]
gdocs = os.environ["_GDTBL_GDOCS"]
from_index = int(os.environ.get("_GDTBL_FROM_INDEX", "0"))
to_index = int(os.environ.get("_GDTBL_TO_INDEX", "0"))  # 0 = no upper bound

def run_gdocs(*args):
    r = subprocess.run([gdocs] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        print(f"gdocs.sh error: {r.stderr}", file=sys.stderr)
        sys.exit(1)
    return r.stdout

def read_doc():
    return json.loads(run_gdocs("read-json", doc_id))

def batch(requests):
    return run_gdocs("batch", doc_id, json.dumps(requests))

# ── Find tab-separated paragraph groups ──────────────────────────

elements = read_doc()

# Extract paragraphs with their text (filtered by --from-index / --to-index if set)
paragraphs = []
for el in elements:
    if "paragraph" in el:
        if el["startIndex"] < from_index:
            continue
        if to_index > 0 and el["endIndex"] > to_index:
            continue
        text = ""
        for e in el["paragraph"].get("elements", []):
            text += e.get("textRun", {}).get("content", "")
        paragraphs.append({
            "startIndex": el["startIndex"],
            "endIndex": el["endIndex"],
            "text": text
        })

if from_index > 0 or to_index > 0:
    bound = f">={from_index}" + (f", <={to_index}" if to_index > 0 else "")
    print(f"Scanning paragraphs in range {bound} ({len(paragraphs)} candidates).", file=sys.stderr)

# Group consecutive tab-containing paragraphs
table_groups = []
current_group = []
for p in paragraphs:
    if "\t" in p["text"]:
        current_group.append(p)
    else:
        if len(current_group) >= 2:  # at least header + 1 data row
            table_groups.append(current_group)
        current_group = []
if len(current_group) >= 2:
    table_groups.append(current_group)

if not table_groups:
    # Check for existing empty tables that need populating
    print("No tab-separated text tables found.", file=sys.stderr)
    sys.exit(0)

print(f"Found {len(table_groups)} text tables to convert.", file=sys.stderr)

# ── Convert each table (in REVERSE order to preserve indices) ────

for group in reversed(table_groups):
    # Parse cells
    rows = []
    for p in group:
        cells = p["text"].rstrip("\n").split("\t")
        rows.append(cells)

    nrows = len(rows)
    ncols = max(len(r) for r in rows)
    # Pad short rows
    for r in rows:
        while len(r) < ncols:
            r.append("")

    start_idx = group[0]["startIndex"]
    end_idx = group[-1]["endIndex"]

    print(f"  Table at {start_idx}-{end_idx}: {nrows}x{ncols}", file=sys.stderr)
    for r in rows:
        print(f"    {r}", file=sys.stderr)

    # Step 1: Delete the text lines
    # Can't delete the trailing \n of the last element in the doc, so be careful
    delete_end = end_idx
    requests = [
        {"deleteContentRange": {"range": {"startIndex": start_idx, "endIndex": delete_end - 1}}}
    ]
    batch(requests)

    # Step 2: Re-read to get fresh index, then insert table
    elements = read_doc()
    # Find where our deletion point is now - it should be at start_idx
    # The \n we left behind is at start_idx, insert table before it
    insert_idx = start_idx

    requests = [
        {"insertTable": {"rows": nrows, "columns": ncols, "location": {"index": insert_idx}}}
    ]
    batch(requests)

    # Step 3: Re-read to get table cell indices, fill cells in reverse
    elements = read_doc()

    # Find the table we just inserted
    table_el = None
    for el in elements:
        if "table" in el and el["startIndex"] >= insert_idx:
            table_el = el
            break

    if not table_el:
        print(f"  ERROR: Could not find inserted table!", file=sys.stderr)
        continue

    # Extract cell paragraph indices from the table structure
    cell_indices = []  # [(row, col, paragraph_start_index)]
    for ri, tr in enumerate(table_el["table"]["tableRows"]):
        for ci, tc in enumerate(tr["tableCells"]):
            # Each cell has content -> paragraph -> startIndex
            para_idx = tc["content"][0]["startIndex"] + 1  # +1 to get inside the paragraph
            # Actually the paragraph startIndex IS the insert point
            para_start = tc["content"][0]["paragraph"]["elements"][0]["startIndex"]
            cell_indices.append((ri, ci, para_start))

    # Fill cells in reverse order
    fill_requests = []
    for ri, ci, idx in reversed(cell_indices):
        text = rows[ri][ci] if ci < len(rows[ri]) else ""
        if text:
            fill_requests.append({
                "insertText": {
                    "location": {"index": idx},
                    "text": text
                }
            })

    if fill_requests:
        batch(fill_requests)

    # Step 4: Re-read and bold header row
    elements = read_doc()
    for el in elements:
        if "table" in el and el["startIndex"] >= insert_idx:
            table_el = el
            break

    first_row = table_el["table"]["tableRows"][0]
    header_start = first_row["tableCells"][0]["content"][0]["startIndex"]
    header_end = first_row["tableCells"][-1]["content"][-1]["endIndex"]

    bold_requests = [{
        "updateTextStyle": {
            "range": {"startIndex": header_start, "endIndex": header_end - 1},
            "textStyle": {"bold": True},
            "fields": "bold"
        }
    }]
    batch(bold_requests)

    print(f"  Done: {nrows}x{ncols} table with bold header.", file=sys.stderr)

print("All tables converted.", file=sys.stderr)
PYEOF
