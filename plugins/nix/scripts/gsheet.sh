#!/usr/bin/env bash
# gsheet.sh — Google Sheets CLI via Sheets API v4
# Uses OAuth token from mcp-google-sheets config for read/write access.
#
# Usage:
#   gsheet.sh info    SPREADSHEET_ID
#   gsheet.sh read    SPREADSHEET_ID [RANGE]
#   gsheet.sh write   SPREADSHEET_ID RANGE VALUE_JSON
#   gsheet.sh append  SPREADSHEET_ID RANGE VALUE_JSON
#   gsheet.sh add-sheet SPREADSHEET_ID SHEET_TITLE
#   gsheet.sh clear   SPREADSHEET_ID RANGE
#   gsheet.sh batch-write SPREADSHEET_ID DATA_JSON
#   gsheet.sh set-note SPREADSHEET_ID CELL NOTE_TEXT
#   gsheet.sh resize SPREADSHEET_ID SHEET_TITLE ROWS COLS
#   gsheet.sh batch  SPREADSHEET_ID REQUESTS_JSON
#
# Examples:
#   gsheet.sh info 1u2X...t00
#   gsheet.sh read 1u2X...t00 "Impact!A1:H5"
#   gsheet.sh write 1u2X...t00 "Impact!E3" '[["4h"]]'
#   gsheet.sh append 1u2X...t00 "Impact!A1" '[["NEW-001","Workflow","Team","Champion"]]'
#   gsheet.sh add-sheet 1u2X...t00 "New Sheet"
#   gsheet.sh clear 1u2X...t00 "Impact!E3:H33"
#   gsheet.sh batch-write 1u2X...t00 '{"data":[{"range":"Impact!E3","values":[["4h"]]},{"range":"Impact!E4","values":[["2h"]]}]}'
#   gsheet.sh resize 1u2X...t00 "Workflow Savings" 34 11
#   gsheet.sh delete-sheet 1u2X...t00 "Impact"
#   gsheet.sh format-font 1u2X...t00 "Sheet1" "Arial" 11
#   gsheet.sh batch 1u2X...t00 '{"requests":[{"updateSheetProperties":{...}}]}'  # raw batchUpdate

set -euo pipefail

# Token: explicit TOKEN_PATH wins; else GOOGLE_PROFILE -> ~/.config/google/<profile>/token.json; else legacy default.
if [ -n "${TOKEN_PATH:-}" ]; then :
elif [ -n "${GOOGLE_PROFILE:-}" ]; then TOKEN_PATH="$HOME/.config/google/${GOOGLE_PROFILE}/token.json"
else TOKEN_PATH="$HOME/.config/mcp-google-sheets/token.json"; fi
API="https://sheets.googleapis.com/v4/spreadsheets"

# ── Token management ──────────────────────────────────────────────

refresh_token() {
  local client_id client_secret refresh_token new_token expires_in expiry

  client_id=$(jq -r '.client_id' "$TOKEN_PATH")
  client_secret=$(jq -r '.client_secret' "$TOKEN_PATH")
  refresh_token=$(jq -r '.refresh_token' "$TOKEN_PATH")

  response=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
    -d "client_id=${client_id}" \
    -d "client_secret=${client_secret}" \
    -d "refresh_token=${refresh_token}" \
    -d "grant_type=refresh_token")

  new_token=$(echo "$response" | jq -r '.access_token // empty')
  if [[ -z "$new_token" ]]; then
    echo "ERROR: Token refresh failed:" >&2
    echo "$response" >&2
    exit 1
  fi

  expires_in=$(echo "$response" | jq -r '.expires_in // 3600')
  expiry=$(date -u -v+"${expires_in}S" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "+${expires_in} seconds" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

  # Update token file in place
  jq --arg t "$new_token" --arg e "$expiry" '.token = $t | .expiry = $e' "$TOKEN_PATH" > "${TOKEN_PATH}.tmp" \
    && mv "${TOKEN_PATH}.tmp" "$TOKEN_PATH"

  echo "$new_token"
}

get_token() {
  local token expiry now

  token=$(jq -r '.token' "$TOKEN_PATH")
  expiry=$(jq -r '.expiry // "1970-01-01T00:00:00Z"' "$TOKEN_PATH")

  # Check if token is expired (with 60s buffer)
  now=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
  if [[ "$now" > "$expiry" ]] || [[ "$now" == "$expiry" ]]; then
    token=$(refresh_token)
  fi

  echo "$token"
}

# ── API helpers ───────────────────────────────────────────────────

check_http() {
  local response="$1" url="$2"
  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: HTTP $http_code from $url" >&2
    echo "$body" | jq '.error // .' >&2 2>/dev/null || echo "$body" >&2
    return 1
  fi
  echo "$body"
}

api_get() {
  local url="$1"
  local token
  token=$(get_token)
  local response
  response=$(curl -s -w $'\n%{http_code}' -H "Authorization: Bearer $token" "$url")
  check_http "$response" "$url"
}

api_post() {
  local url="$1" body="$2"
  local token
  token=$(get_token)
  local response
  response=$(curl -s -w $'\n%{http_code}' -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$url")
  check_http "$response" "$url"
}

api_put() {
  local url="$1" body="$2"
  local token
  token=$(get_token)
  local response
  response=$(curl -s -w $'\n%{http_code}' -X PUT \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$url")
  check_http "$response" "$url"
}

# ── Commands ──────────────────────────────────────────────────────

cmd_info() {
  local sid="$1"
  api_get "${API}/${sid}?fields=properties,sheets.properties" | jq .
}

cmd_read() {
  local sid="$1" range="${2:-}"
  range="${range//\\!/!}"
  if [[ -z "$range" ]]; then
    api_get "${API}/${sid}/values/%21A1%3AZZ10000" | jq .
  else
    local encoded_range
    encoded_range=$(printf '%s' "$range" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))")
    api_get "${API}/${sid}/values/${encoded_range}" | jq .
  fi
}

cmd_write() {
  local sid="$1" range="$2" values="$3"
  range="${range//\\!/!}"
  local encoded_range
  encoded_range=$(printf '%s' "$range" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))")
  local body
  body=$(jq -n --arg r "$range" --argjson v "$values" '{range: $r, values: $v, majorDimension: "ROWS"}')
  api_put "${API}/${sid}/values/${encoded_range}?valueInputOption=USER_ENTERED" "$body" | jq .
}

cmd_append() {
  local sid="$1" range="$2" values="$3"
  range="${range//\\!/!}"
  local encoded_range
  encoded_range=$(printf '%s' "$range" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))")
  local body
  body=$(jq -n --arg r "$range" --argjson v "$values" '{range: $r, values: $v, majorDimension: "ROWS"}')
  api_post "${API}/${sid}/values/${encoded_range}:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS" "$body" | jq .
}

cmd_add_sheet() {
  local sid="$1" title="$2"
  local body
  body=$(jq -n --arg t "$title" '{requests: [{addSheet: {properties: {title: $t}}}]}')
  api_post "${API}/${sid}:batchUpdate" "$body" | jq .
}

cmd_clear() {
  local sid="$1" range="$2"
  range="${range//\\!/!}"
  local encoded_range
  encoded_range=$(printf '%s' "$range" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))")
  api_post "${API}/${sid}/values/${encoded_range}:clear" '{}' | jq .
}

cmd_batch_write() {
  local sid="$1" data_json="$2"
  local body
  body=$(jq -n --argjson d "$data_json" '{valueInputOption: "USER_ENTERED", data: $d.data}')
  api_post "${API}/${sid}/values:batchUpdate" "$body" | jq .
}

_get_sheet_id() {
  local sid="$1" title="$2"
  api_get "${API}/${sid}?fields=sheets.properties" \
    | jq -r --arg t "$title" '.sheets[] | select(.properties.title == $t) | .properties.sheetId'
}

cmd_delete_sheet() {
  local sid="$1" title="$2"
  local sheet_id
  sheet_id=$(_get_sheet_id "$sid" "$title")

  if [[ -z "$sheet_id" ]]; then
    echo "ERROR: Sheet '$title' not found" >&2
    exit 1
  fi

  local body
  body=$(jq -n --argjson sid "$sheet_id" '{requests: [{deleteSheet: {sheetId: $sid}}]}')
  api_post "${API}/${sid}:batchUpdate" "$body" | jq .
}

cmd_format_font() {
  local sid="$1" title="$2" font="$3" size="$4"
  local sheet_id
  sheet_id=$(_get_sheet_id "$sid" "$title")

  if [[ -z "$sheet_id" ]]; then
    echo "ERROR: Sheet '$title' not found" >&2
    exit 1
  fi

  local body
  body=$(jq -n \
    --argjson sid "$sheet_id" \
    --arg f "$font" \
    --argjson s "$size" \
    '{requests: [{repeatCell: {
      range: {sheetId: $sid},
      cell: {userEnteredFormat: {textFormat: {fontFamily: $f, fontSize: $s}}},
      fields: "userEnteredFormat.textFormat.fontFamily,userEnteredFormat.textFormat.fontSize"
    }}]}')
  api_post "${API}/${sid}:batchUpdate" "$body" | jq .
}

cmd_resize() {
  local sid="$1" title="$2" rows="$3" cols="$4"

  local sheet_id
  sheet_id=$(_get_sheet_id "$sid" "$title")

  if [[ -z "$sheet_id" ]]; then
    echo "ERROR: Sheet '$title' not found" >&2
    exit 1
  fi

  local body
  body=$(jq -n \
    --argjson sid "$sheet_id" \
    --argjson r "$rows" \
    --argjson c "$cols" \
    '{requests: [
      {updateSheetProperties: {
        properties: {sheetId: $sid, gridProperties: {rowCount: $r, columnCount: $c}},
        fields: "gridProperties.rowCount,gridProperties.columnCount"
      }}
    ]}')
  api_post "${API}/${sid}:batchUpdate" "$body" | jq .
}

cmd_batch() {
  local sid="$1" requests_json="$2"
  api_post "${API}/${sid}:batchUpdate" "$requests_json" | jq .
}

cmd_set_note() {
  local sid="$1" cell="$2" note="$3"
  cell="${cell//\\!/!}"

  # Parse "Sheet!A1" into sheet name + row + col
  local sheet_name col_letter row_num
  sheet_name="${cell%%!*}"
  local cell_ref="${cell#*!}"
  col_letter="${cell_ref%%[0-9]*}"
  row_num="${cell_ref##*[A-Za-z]}"

  # Convert column letter(s) to 0-based index
  local col_index=0 i char
  for (( i=0; i<${#col_letter}; i++ )); do
    char="${col_letter:$i:1}"
    col_index=$(( col_index * 26 + $(printf '%d' "'$char") - 64 ))
  done
  col_index=$(( col_index - 1 ))
  local row_index=$(( row_num - 1 ))

  local sheet_id
  sheet_id=$(_get_sheet_id "$sid" "$sheet_name")
  if [[ -z "$sheet_id" ]]; then
    echo "ERROR: Sheet '$sheet_name' not found" >&2
    exit 1
  fi

  local body
  body=$(jq -n \
    --argjson sheetId "$sheet_id" \
    --argjson row "$row_index" \
    --argjson col "$col_index" \
    --arg note "$note" \
    '{requests: [{repeatCell: {
        range: {sheetId: $sheetId, startRowIndex: $row, endRowIndex: ($row + 1), startColumnIndex: $col, endColumnIndex: ($col + 1)},
        cell: {note: $note},
        fields: "note"
      }}]}')
  api_post "${API}/${sid}:batchUpdate" "$body" | jq .
}

# Helper: look up sheetId used by resize (kept for backwards compat)
# _get_sheet_id is defined above and shared by delete-sheet, format-font, resize, set-note

# ── Main ──────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  head -20 "$0" | grep '^#' | sed 's/^# \?//'
  exit 1
fi

cmd="$1"; shift

case "$cmd" in
  info)        cmd_info "$@" ;;
  read)        cmd_read "$@" ;;
  write)       cmd_write "$@" ;;
  append)      cmd_append "$@" ;;
  add-sheet)   cmd_add_sheet "$@" ;;
  clear)       cmd_clear "$@" ;;
  batch-write)   cmd_batch_write "$@" ;;
  resize)        cmd_resize "$@" ;;
  delete-sheet)  cmd_delete_sheet "$@" ;;
  set-note)      cmd_set_note "$@" ;;
  format-font)   cmd_format_font "$@" ;;
  batch)         cmd_batch "$@" ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Commands: info, read, write, append, add-sheet, delete-sheet, clear, batch-write, resize, set-note, format-font, batch" >&2
    exit 1
    ;;
esac
