---
name: google
description: "Use when reading or editing Google Docs, Sheets, Slides, or Drive files — read a doc as text/JSON, batch-format or edit a doc, read/write sheets, read/replace/export slides, list/search Drive. Driven by the bundled gdocs.sh / gsheet.sh / gslides.sh / gdrive.sh, which take the account profile as their FIRST arg (nix for N-iX, personal for personal). Shell + curl + jq, no MCP. Trigger on any docs.google.com / drive.google.com Google file request."
---

# nix:google — Google Docs/Sheets/Slides/Drive CLI for the N-iX workspace

Drive Google Workspace via bundled shell/`curl`/`jq` CLIs. No install.

## Scripts

Bundled with this plugin under `${CLAUDE_PLUGIN_ROOT}/scripts/` — always reference via `${CLAUDE_PLUGIN_ROOT}` (plugins get cached; hardcoded paths break):
- `gdocs.sh` — Google Docs (read, batch edit/format, comments)
- `gsheet.sh` — Google Sheets
- `gslides.sh` — Google Slides (read text/structure, find-replace, export)
- `gdrive.sh` — Google Drive (list/search/download)
- `gdoc2md.py` — Doc → Markdown helper

## Auth — account profile is the FIRST arg

Every script takes the **account profile as its first positional argument** — it names the OAuth token at `~/.config/google/<profile>/token.json` (the scripts auto-refresh the short-lived access token). Resolution order: `TOKEN_PATH` env override → `GOOGLE_PROFILE` env → **first positional arg**.

- **N-iX docs → `nix`:** `"$G" nix read DOC_ID` → `~/.config/google/nix/token.json`.
- **Personal (or any other account) → its profile name:** `"$G" personal read DOC_ID`. **Same scripts, one skill — just swap the profile;** never use `personal` for N-iX content, or `nix` for personal.
- The env form still works for existing callers: `"$G" nix read DOC_ID`.

The token is global — works from any directory.

## Commands (gdocs.sh)

```bash
G="${CLAUDE_PLUGIN_ROOT}/scripts/gdocs.sh"
"$G" nix get       DOC_ID          # title + revisionId
"$G" nix read      DOC_ID          # full document as plain text
"$G" nix read-json DOC_ID          # body.content array (structural elements → char indices)
"$G" nix replace   DOC_ID "FIND" "REPLACE"
"$G" nix append    DOC_ID "text"
"$G" nix insert    DOC_ID INDEX "text"
"$G" nix batch     DOC_ID '<json-array-of-batchUpdate-requests>'   # raw edits/formatting
"$G" nix comments  DOC_ID [--include-resolved]
```

The DOC_ID is the long string in the URL: `docs.google.com/document/d/<DOC_ID>/edit`.

## Commands (gslides.sh)

```bash
S="${CLAUDE_PLUGIN_ROOT}/scripts/gslides.sh"
"$S" nix info    PRESENTATION_ID              # presentationId, page size, slide objectIds
"$S" nix text    PRESENTATION_ID [SLIDE_IDX]  # all slides' text (or one slide, 0-indexed)
"$S" nix slides  PRESENTATION_ID              # list slide objectIds (p1, p2, …)
"$S" nix slide   PRESENTATION_ID SLIDE_IDX    # one slide's elements/structure
"$S" nix replace PRESENTATION_ID "OLD" "NEW"  # find/replace text across the deck
"$S" nix export  PRESENTATION_ID              # export (PDF via Drive)
# also: shapes · set-text · set-font · duplicate · delete · batch (raw batchUpdate)
```

The PRESENTATION_ID is the long string in the URL: `docs.google.com/presentation/d/<PRESENTATION_ID>/edit`.
The `#slide=id.pN` fragment is the slide's objectId — `pN` is the N-th slide (`text PRESENTATION_ID N-1` reads it 0-indexed).

## Sheets / Drive

`gsheet.sh` and `gdrive.sh` share the same profile-first convention — pass the profile as the first arg (e.g. `gsheet.sh nix read …`). Run the script with no args for its usage.

## Recipes

- **Read a shared doc:** `"$G" nix read DOC_ID`.
- **Read a deck (or one slide):** `"$S" nix text PRESENTATION_ID` for the whole deck; append the 0-indexed slide number for just one (`#slide=id.p3` → `text PRESENTATION_ID 2`).
- **Fit a doc to one page (formatting, not text cuts):** get indices with `read-json` (returns the `body.content` array — last `endIndex` + heading ranges), then `batch` with: `updateDocumentStyle` margins 36pt top/bottom, 54pt left/right; `updateParagraphStyle` over `{startIndex:1, endIndex:<last-1>}` → `lineSpacing:100`, `spaceAbove/Below:0`; `updateTextStyle` on heading ranges → smaller `fontSize`.
- **Targeted wording change:** `replace DOC_ID "old" "new"` (exact match, keeps formatting).

## Gotchas

- `read-json` returns the **`body.content` array**, not the whole document object — index it directly; `documentStyle`/margins are **not** in that output (set them blind via `batch`; the request still succeeds).
- `batch` expects a **JSON array of request objects**; the script wraps it as `{requests: [...]}`. Style updates return empty `{}` replies on success.
- Markdown pasted into Google Docs brings Heading styles with large space-above — that (not word count) is usually why a short doc spills to 2 pages; fix with the formatting `batch` above.
- Confidentiality: N-iX doc content stays in N-iX contexts; don't copy it into personal repos.
