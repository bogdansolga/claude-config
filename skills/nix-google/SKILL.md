---
name: nix-google
description: "Use when reading or editing Google Docs, Sheets, or Drive files in the N-iX Google workspace — read a doc as text/JSON, batch-format or edit a doc, read/write sheets, list/search Drive. Driven by gdocs.sh / gsheet.sh / gdrive.sh with GOOGLE_PROFILE=n-ix (shell + curl + jq, no MCP). Trigger on any docs.google.com / drive.google.com / N-iX Google file request."
---

# nix-google — Google Docs/Sheets/Drive CLI for the N-iX workspace

Drive Google Workspace via shell/`curl`/`jq` CLIs. No MCP, no install.

## Scripts

In `~/.claude/skills/nix-google/scripts/`:
- `gdocs.sh` — Google Docs (read, batch edit/format, comments)
- `gsheet.sh` — Google Sheets
- `gdrive.sh` — Google Drive (list/search/download)
- `gdoc2md.py` — Doc → Markdown helper

## Auth — n-ix profile (do this every call)

Token resolution: `TOKEN_PATH` env wins → else **`GOOGLE_PROFILE=<profile>` → `~/.config/google/<profile>/token.json`** → else a legacy default. **For all N-iX docs prefix every command with `GOOGLE_PROFILE=n-ix`** → `~/.config/google/n-ix/token.json` (OAuth refresh token; the scripts auto-refresh the short-lived access token). A **`personal`** profile also exists — do **not** use it for n-ix content. This token is global — the scripts work from any directory.

## Commands (gdocs.sh)

```bash
G=~/.claude/skills/nix-google/scripts/gdocs.sh
GOOGLE_PROFILE=n-ix "$G" get       DOC_ID          # title + revisionId
GOOGLE_PROFILE=n-ix "$G" read      DOC_ID          # full document as plain text
GOOGLE_PROFILE=n-ix "$G" read-json DOC_ID          # body.content array (structural elements → char indices)
GOOGLE_PROFILE=n-ix "$G" replace   DOC_ID "FIND" "REPLACE"
GOOGLE_PROFILE=n-ix "$G" append    DOC_ID "text"
GOOGLE_PROFILE=n-ix "$G" insert    DOC_ID INDEX "text"
GOOGLE_PROFILE=n-ix "$G" batch     DOC_ID '<json-array-of-batchUpdate-requests>'   # raw edits/formatting
GOOGLE_PROFILE=n-ix "$G" comments  DOC_ID [--include-resolved]
```

The DOC_ID is the long string in the doc URL: `docs.google.com/document/d/<DOC_ID>/edit`.

## Sheets / Drive

`gsheet.sh` and `gdrive.sh` share the same token pattern — always prefix `GOOGLE_PROFILE=n-ix`. Run the script with no args for its usage/commands.

## Recipes

- **Read a shared doc:** `GOOGLE_PROFILE=n-ix "$G" read DOC_ID`.
- **Fit a doc to one page (formatting, not text cuts):** get indices with `read-json` (returns the `body.content` array; find the last `endIndex` and heading ranges), then `batch` with:
  - `updateDocumentStyle` → margins 36pt top/bottom, 54pt left/right;
  - `updateParagraphStyle` over `{startIndex:1, endIndex:<last-1>}` → `lineSpacing:100`, `spaceAbove/Below: 0`;
  - `updateTextStyle` on heading ranges → smaller `fontSize`.
- **Targeted wording change:** `replace DOC_ID "old" "new"` (exact match, keeps formatting).

## Gotchas

- `read-json` returns the **`body.content` array**, not the whole document object — index it directly (`.[]`), and note `documentStyle`/margins are **not** in that output (set them blind via `batch`; the request still succeeds).
- `batch` expects a **JSON array of request objects**; the script wraps it as `{requests: [...]}`. Style-update requests return empty `{}` replies on success.
- Markdown pasted into Google Docs brings Heading styles with large space-above — that (not word count) is usually why a short doc spills to 2 pages; fix with the formatting `batch` above.
- Confidentiality: N-iX doc content stays in N-iX contexts; don't copy it into personal repos.
