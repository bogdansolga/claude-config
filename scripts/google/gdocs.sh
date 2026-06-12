#!/usr/bin/env bash
# gdocs.sh — Google Docs CLI via Docs API v1 (+ Drive API v3 for comments)
# Reuses OAuth token from mcp-google-sheets config (drive scope covers Docs).
#
# Usage:
#   gdocs.sh get       DOCUMENT_ID                    # Get document metadata (title, revisionId)
#   gdocs.sh read      DOCUMENT_ID                    # Read full document as plain text
#   gdocs.sh read-json DOCUMENT_ID                    # Read full document as raw JSON (structural elements)
#   gdocs.sh comments  DOCUMENT_ID [--include-resolved] # List comments + replies (Drive API v3)
#   gdocs.sh insert    DOCUMENT_ID INDEX TEXT          # Insert text at character index
#   gdocs.sh append    DOCUMENT_ID TEXT                # Append text at end of document
#   gdocs.sh replace   DOCUMENT_ID FIND REPLACE        # Find and replace text
#   gdocs.sh checkbox  DOCUMENT_ID START_INDEX END_INDEX # Convert paragraph range to checkboxes
#   gdocs.sh batch     DOCUMENT_ID REQUESTS_JSON       # Send raw batchUpdate requests
#   gdocs.sh create    TITLE                           # Create a new empty document
#
# Checkbox workflow (two-step):
#   1. Insert text:    gdocs.sh append DOC_ID "Item one\nItem two\nItem three"
#   2. Make checkboxes: gdocs.sh checkbox DOC_ID START_INDEX END_INDEX
#      - START_INDEX/END_INDEX: character indices of the paragraph range (use read-json to find them)
#      - Uses BULLET_CHECKBOX preset via createParagraphBullets
#      - Checked state is NOT controllable via API — checkboxes are always unchecked when created
#
# Examples:
#   gdocs.sh get 1pS2xf1C-917RLc6-EAO9baXPPd4aZCVw21PHpeLwM_4
#   gdocs.sh read 1pS2xf1C-917RLc6-EAO9baXPPd4aZCVw21PHpeLwM_4
#   gdocs.sh append 1pS2xf1C-917RLc6-EAO9baXPPd4aZCVw21PHpeLwM_4 "New paragraph text"
#   gdocs.sh replace 1pS2xf1C-917RLc6-EAO9baXPPd4aZCVw21PHpeLwM_4 "OLD_TEXT" "NEW_TEXT"
#   gdocs.sh create "Meeting Notes — 2026-04-02"
#   gdocs.sh checkbox 1pS2xf1C... 208 433   # Convert lines at indices 208-433 to checkboxes

set -euo pipefail

TOKEN_PATH="${TOKEN_PATH:-$HOME/.config/mcp-google-sheets/token.json}"
API="https://docs.googleapis.com/v1/documents"
DRIVE_API="https://www.googleapis.com/drive/v3/files"

# ── Token management (shared with gsheet.sh) ─────────────────────

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

  jq --arg t "$new_token" --arg e "$expiry" '.token = $t | .expiry = $e' "$TOKEN_PATH" > "${TOKEN_PATH}.tmp" \
    && mv "${TOKEN_PATH}.tmp" "$TOKEN_PATH"

  echo "$new_token"
}

get_token() {
  local token expiry now

  token=$(jq -r '.token' "$TOKEN_PATH")
  expiry=$(jq -r '.expiry // "1970-01-01T00:00:00Z"' "$TOKEN_PATH")

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

# ── Commands ──────────────────────────────────────────────────────

cmd_get() {
  local doc_id="$1"
  api_get "${API}/${doc_id}" | jq '{title: .title, documentId: .documentId, revisionId: .revisionId}'
}

cmd_read() {
  local doc_id="$1"
  api_get "${API}/${doc_id}" | jq -r '
    [.body.content[]? |
      .paragraph?.elements[]?.textRun?.content // empty
    ] | join("")'
}

cmd_read_json() {
  local doc_id="$1"
  api_get "${API}/${doc_id}" | jq '.body.content'
}

cmd_comments() {
  local doc_id="$1"
  local include_resolved="false"
  shift || true
  for arg in "$@"; do
    [[ "$arg" == "--include-resolved" ]] && include_resolved="true"
  done

  local fields="comments(id,author(displayName),content,quotedFileContent(value),resolved,createdTime,modifiedTime,replies(author(displayName),content,createdTime))"
  local url="${DRIVE_API}/${doc_id}/comments?fields=${fields}&includeDeleted=false&pageSize=100"

  api_get "$url" | jq --argjson inc "$include_resolved" '
    .comments
    | map(select($inc or (.resolved // false) == false))
    | map({
        id,
        author: .author.displayName,
        created: .createdTime,
        modified: .modifiedTime,
        resolved: (.resolved // false),
        anchor: (.quotedFileContent.value // null),
        content,
        replies: (.replies // [] | map({
          author: .author.displayName,
          created: .createdTime,
          content
        }))
      })
  '
}

cmd_insert() {
  local doc_id="$1" index="$2" text="$3"
  local body
  body=$(jq -n --argjson idx "$index" --arg txt "$text" '{
    requests: [{
      insertText: {
        location: { index: $idx },
        text: $txt
      }
    }]
  }')
  api_post "${API}/${doc_id}:batchUpdate" "$body" | jq '.replies'
}

cmd_append() {
  local doc_id="$1" text="$2"
  # Get the end index of the document body
  local end_index
  end_index=$(api_get "${API}/${doc_id}" | jq '.body.content[-1].endIndex - 1')

  local body
  body=$(jq -n --argjson idx "$end_index" --arg txt "$text" '{
    requests: [{
      insertText: {
        location: { index: $idx },
        text: ("\n" + $txt)
      }
    }]
  }')
  api_post "${API}/${doc_id}:batchUpdate" "$body" | jq '.replies'
}

cmd_replace() {
  local doc_id="$1" find_text="$2" replace_text="$3"
  local body
  body=$(jq -n --arg find "$find_text" --arg replace "$replace_text" '{
    requests: [{
      replaceAllText: {
        containsText: {
          text: $find,
          matchCase: true
        },
        replaceText: $replace
      }
    }]
  }')
  api_post "${API}/${doc_id}:batchUpdate" "$body" | jq '.replies'
}

cmd_checkbox() {
  local doc_id="$1" start_index="$2" end_index="$3"
  local body
  body=$(jq -n --argjson start "$start_index" --argjson end "$end_index" '{
    requests: [{
      createParagraphBullets: {
        range: {
          startIndex: $start,
          endIndex: $end
        },
        bulletPreset: "BULLET_CHECKBOX"
      }
    }]
  }')
  api_post "${API}/${doc_id}:batchUpdate" "$body" | jq '.replies'
}

cmd_batch() {
  local doc_id="$1" requests_json="$2"
  local body
  body=$(jq -n --argjson reqs "$requests_json" '{ requests: $reqs }')
  api_post "${API}/${doc_id}:batchUpdate" "$body" | jq '.replies'
}

cmd_create() {
  local title="$1"
  local body
  body=$(jq -n --arg t "$title" '{ title: $t }')
  api_post "${API}" "$body" | jq '{documentId: .documentId, title: .title}'
}

# ── Main ──────────────────────────────────────────────────────────

cmd_help() {
  cat <<'EOF'
gdocs.sh — Google Docs CLI via Docs API v1

Commands:
  help                                     Show this help message
  get       DOCUMENT_ID                    Get document metadata (title, revisionId)
  read      DOCUMENT_ID                    Read full document as plain text
  read-json DOCUMENT_ID                    Read full document as raw JSON (structural elements)
  comments  DOCUMENT_ID [--include-resolved]
                                           List comments + replies (Drive API v3)
  insert    DOCUMENT_ID INDEX TEXT          Insert text at character index
  append    DOCUMENT_ID TEXT               Append text at end of document
  replace   DOCUMENT_ID FIND REPLACE       Find and replace text
  checkbox  DOCUMENT_ID START_IDX END_IDX  Convert paragraph range to checkboxes
  batch     DOCUMENT_ID REQUESTS_JSON      Send raw batchUpdate requests
  create    TITLE                          Create a new empty document

Checkbox workflow (two-step):
  1. Insert text:     gdocs.sh append DOC_ID "Item one\nItem two\nItem three"
  2. Make checkboxes: gdocs.sh checkbox DOC_ID START_INDEX END_INDEX
     Use read-json to find character indices.

Examples:
  gdocs.sh get 1pS2xf1C-917RLc6-EAO9baXPPd4aZCVw21PHpeLwM_4
  gdocs.sh read 1pS2xf1C-917RLc6-EAO9baXPPd4aZCVw21PHpeLwM_4
  gdocs.sh append 1pS2xf1C... "New paragraph text"
  gdocs.sh replace 1pS2xf1C... "OLD_TEXT" "NEW_TEXT"
  gdocs.sh create "Meeting Notes — 2026-04-16"
  gdocs.sh checkbox 1pS2xf1C... 208 433

Related scripts:
  md2gdoc.sh      Convert Markdown file to formatted Google Doc
  gdoc-tables.sh  Convert tab-separated text to native Google Docs tables
  gsheet.sh       Google Sheets CLI
  gslides.sh      Google Slides CLI
EOF
}

# ── Main ──────────────────────────────────────────────────────────

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
  help|-h|--help) cmd_help ;;
  get)       cmd_get "$@" ;;
  read)      cmd_read "$@" ;;
  read-json) cmd_read_json "$@" ;;
  comments)  cmd_comments "$@" ;;
  insert)    cmd_insert "$@" ;;
  append)    cmd_append "$@" ;;
  replace)   cmd_replace "$@" ;;
  checkbox)  cmd_checkbox "$@" ;;
  batch)     cmd_batch "$@" ;;
  create)    cmd_create "$@" ;;
  *)         echo "Unknown command: $cmd" >&2; cmd_help; exit 1 ;;
esac
