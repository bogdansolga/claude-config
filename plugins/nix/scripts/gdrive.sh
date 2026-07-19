#!/usr/bin/env bash
# gdrive.sh — Google Drive file management CLI via Drive API v3
# Reuses OAuth token from mcp-google-sheets config (drive scope). Auto-refreshes.
#
# Scope: generic Drive *file* operations — upload arbitrary files, list, make
# folders, export, and replace content. For Docs/Sheets/Slides *content* editing
# use the surface-specific scripts instead:
#   - gdocs.sh    — Docs API (read/insert/append/replace/checkbox/create)
#   - md2gdoc.sh  — Markdown → Google Doc with NATIVE formatting (preferred over
#                   `gdrive.sh upload --as-doc`, which uses Drive's lossy import)
#   - gsheet.sh   — Sheets API   |   gslides.sh — Slides API
#
# Usage:
#   gdrive.sh upload <file> [--name NAME] [--folder FOLDER_ID] [--as-doc]
#   gdrive.sh list [--folder FOLDER_ID] [--query "name contains 'x'"]
#   gdrive.sh mkdir <name> [--parent FOLDER_ID]
#   gdrive.sh export <fileId> [--mime text/markdown] [--out FILE]
#   gdrive.sh update <fileId> <file> [--as-doc]      # replace existing file's content
#
# Examples:
#   gdrive.sh upload deck.pptx                          # raw upload into My Drive
#   gdrive.sh upload notes.md --as-doc --name "Notes"   # quick (lossy) convert to Doc
#   gdrive.sh export 1I9WX... --mime text/markdown --out /tmp/doc.md
#   gdrive.sh update 1I9WX... notes.md --as-doc         # same URL, content replaced
#   gdrive.sh mkdir "UTA Workshop"
#   gdrive.sh list --query "name contains 'Workshop'"
#
set -euo pipefail

# Token: explicit TOKEN_PATH wins; else GOOGLE_PROFILE -> ~/.config/google/<profile>/token.json; else legacy default.
if [ -n "${TOKEN_PATH:-}" ]; then :
elif [ -n "${GOOGLE_PROFILE:-}" ]; then TOKEN_PATH="$HOME/.config/google/${GOOGLE_PROFILE}/token.json"
else TOKEN_PATH="$HOME/.config/mcp-google-sheets/token.json"; fi

die() { echo "Error: $*" >&2; exit 1; }

[ -f "$TOKEN_PATH" ] || die "token file not found: $TOKEN_PATH"
command -v jq   >/dev/null || die "jq not installed"
command -v curl >/dev/null || die "curl not installed"

# ── Token management (shared pattern with gdocs.sh / gsheet.sh) ──────────────
access_token() {
  local cid csecret rtoken uri access
  cid=$(jq -r '.client_id' "$TOKEN_PATH")
  csecret=$(jq -r '.client_secret' "$TOKEN_PATH")
  rtoken=$(jq -r '.refresh_token' "$TOKEN_PATH")
  uri=$(jq -r '.token_uri // "https://oauth2.googleapis.com/token"' "$TOKEN_PATH")
  access=$(curl -s -X POST "$uri" \
    -d client_id="$cid" -d client_secret="$csecret" \
    -d refresh_token="$rtoken" -d grant_type=refresh_token | jq -r '.access_token // empty')
  [ -n "$access" ] || die "token refresh failed"
  printf '%s' "$access"
}

# Best-effort mime type from file extension.
mime_for() {
  case "${1##*.}" in
    md|markdown) echo "text/markdown" ;;
    txt)         echo "text/plain" ;;
    csv)         echo "text/csv" ;;
    json)        echo "application/json" ;;
    pdf)         echo "application/pdf" ;;
    html|htm)    echo "text/html" ;;
    pptx)        echo "application/vnd.openxmlformats-officedocument.presentationml.presentation" ;;
    docx)        echo "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
    xlsx)        echo "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ;;
    *)           echo "application/octet-stream" ;;
  esac
}

cmd_upload() {
  local file="" name="" folder="" as_doc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)   name="$2"; shift 2 ;;
      --folder) folder="$2"; shift 2 ;;
      --as-doc) as_doc=1; shift ;;
      -*)       die "unknown flag: $1" ;;
      *)        file="$1"; shift ;;
    esac
  done
  [ -n "$file" ] || die "upload: missing <file>"
  [ -f "$file" ] || die "upload: file not found: $file"
  [ -n "$name" ] || name="$(basename "$file")"

  local src_mime metadata access boundary body resp
  src_mime="$(mime_for "$file")"
  if [ "$as_doc" -eq 1 ]; then
    metadata=$(jq -n --arg name "$name" '{name: $name, mimeType: "application/vnd.google-apps.document"}')
  else
    metadata=$(jq -n --arg name "$name" --arg mt "$src_mime" '{name: $name, mimeType: $mt}')
  fi
  if [ -n "$folder" ]; then
    metadata=$(printf '%s' "$metadata" | jq --arg f "$folder" '. + {parents: [$f]}')
  fi

  access="$(access_token)"
  boundary="===gdrive-sh-boundary==="
  body="$(mktemp)"
  trap 'rm -f "$body"' RETURN
  {
    printf -- '--%s\r\n' "$boundary"
    printf 'Content-Type: application/json; charset=UTF-8\r\n\r\n'
    printf '%s\r\n' "$metadata"
    printf -- '--%s\r\n' "$boundary"
    printf 'Content-Type: %s\r\n\r\n' "$src_mime"
    cat "$file"
    printf '\r\n--%s--\r\n' "$boundary"
  } > "$body"

  resp=$(curl -s -X POST \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id,name,mimeType,webViewLink" \
    -H "Authorization: Bearer $access" \
    -H "Content-Type: multipart/related; boundary=$boundary" \
    --data-binary @"$body")
  echo "$resp" | jq .
}

cmd_list() {
  local folder="" query="" access q
  while [ $# -gt 0 ]; do
    case "$1" in
      --folder) folder="$2"; shift 2 ;;
      --query)  query="$2"; shift 2 ;;
      *)        die "unknown arg: $1" ;;
    esac
  done
  q="trashed = false"
  [ -n "$folder" ] && q="$q and '$folder' in parents"
  [ -n "$query" ]  && q="$q and ($query)"
  access="$(access_token)"
  curl -s -G "https://www.googleapis.com/drive/v3/files" \
    -H "Authorization: Bearer $access" \
    --data-urlencode "q=$q" \
    --data-urlencode "fields=files(id,name,mimeType,webViewLink,modifiedTime)" \
    --data-urlencode "pageSize=50" \
    --data-urlencode "supportsAllDrives=true" \
    --data-urlencode "includeItemsFromAllDrives=true" | jq .
}

cmd_mkdir() {
  local name="" parent="" access metadata
  while [ $# -gt 0 ]; do
    case "$1" in
      --parent) parent="$2"; shift 2 ;;
      -*)       die "unknown flag: $1" ;;
      *)        name="$1"; shift ;;
    esac
  done
  [ -n "$name" ] || die "mkdir: missing <name>"
  metadata=$(jq -n --arg name "$name" '{name: $name, mimeType: "application/vnd.google-apps.folder"}')
  [ -n "$parent" ] && metadata=$(printf '%s' "$metadata" | jq --arg p "$parent" '. + {parents: [$p]}')
  access="$(access_token)"
  curl -s -X POST "https://www.googleapis.com/drive/v3/files?fields=id,name,webViewLink&supportsAllDrives=true" \
    -H "Authorization: Bearer $access" \
    -H "Content-Type: application/json" \
    -d "$metadata" | jq .
}

# Export a native Google Doc/Sheet/Slide to a downloadable format (default markdown).
cmd_export() {
  local id="" mime="text/markdown" out="" access
  while [ $# -gt 0 ]; do
    case "$1" in
      --mime) mime="$2"; shift 2 ;;
      --out)  out="$2"; shift 2 ;;
      -*)     die "unknown flag: $1" ;;
      *)      id="$1"; shift ;;
    esac
  done
  [ -n "$id" ] || die "export: missing <fileId>"
  access="$(access_token)"
  if [ -n "$out" ]; then
    curl -s -G "https://www.googleapis.com/drive/v3/files/$id/export" \
      -H "Authorization: Bearer $access" \
      --data-urlencode "mimeType=$mime" -o "$out"
    echo "Wrote $out"
  else
    curl -s -G "https://www.googleapis.com/drive/v3/files/$id/export" \
      -H "Authorization: Bearer $access" \
      --data-urlencode "mimeType=$mime"
  fi
}

# Replace the content of an existing Drive file (keeps the same id / URL).
# --as-doc re-imports as a native Google Doc (Drive's lossy markdown→Doc convert).
cmd_update() {
  local id="" file="" as_doc=0 access src_mime params resp
  while [ $# -gt 0 ]; do
    case "$1" in
      --as-doc) as_doc=1; shift ;;
      -*)       die "unknown flag: $1" ;;
      *)        if [ -z "$id" ]; then id="$1"; else file="$1"; fi; shift ;;
    esac
  done
  [ -n "$id" ] || die "update: missing <fileId>"
  [ -n "$file" ] || die "update: missing <file>"
  [ -f "$file" ] || die "update: file not found: $file"

  src_mime="$(mime_for "$file")"
  params="uploadType=media&supportsAllDrives=true&fields=id,name,mimeType,webViewLink"
  [ "$as_doc" -eq 1 ] && params="$params&mimeType=application/vnd.google-apps.document"

  access="$(access_token)"
  resp=$(curl -s -X PATCH \
    "https://www.googleapis.com/upload/drive/v3/files/$id?$params" \
    -H "Authorization: Bearer $access" \
    -H "Content-Type: $src_mime" \
    --data-binary @"$file")
  echo "$resp" | jq .
}

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 1 ] || { usage; exit 1; }
sub="$1"; shift
case "$sub" in
  upload) cmd_upload "$@" ;;
  list)   cmd_list "$@" ;;
  mkdir)  cmd_mkdir "$@" ;;
  export) cmd_export "$@" ;;
  update) cmd_update "$@" ;;
  -h|--help|help) usage ;;
  *)      die "unknown subcommand: $sub (try: upload | list | mkdir | export | update)" ;;
esac
