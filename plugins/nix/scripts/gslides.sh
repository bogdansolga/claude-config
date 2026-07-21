#!/usr/bin/env bash
# gslides.sh — Google Slides CLI via Slides API v1
# Uses OAuth token from mcp-google-sheets config for read/write access.
#
# Usage:
#   gslides.sh info       PRESENTATION_ID
#   gslides.sh text       PRESENTATION_ID [SLIDE_INDEX]
#   gslides.sh slides     PRESENTATION_ID
#   gslides.sh slide      PRESENTATION_ID SLIDE_INDEX
#   gslides.sh replace    PRESENTATION_ID OLD_TEXT NEW_TEXT
#   gslides.sh duplicate  PRESENTATION_ID SLIDE_OBJECT_ID
#   gslides.sh delete     PRESENTATION_ID SLIDE_OBJECT_ID
#   gslides.sh set-text   PRESENTATION_ID SHAPE_OBJECT_ID NEW_TEXT   # keeps style
#   gslides.sh set-cell   PRESENTATION_ID TABLE_OBJECT_ID ROW COL NEW_TEXT  # keeps style
#   gslides.sh set-font   PRESENTATION_ID FONT_FAMILY [SHAPE_OBJECT_ID]
#   gslides.sh batch      PRESENTATION_ID REQUESTS_JSON
#   gslides.sh shapes     PRESENTATION_ID SLIDE_INDEX
#   gslides.sh dump       PRESENTATION_ID SLIDE_INDEX   # tables (cells) + shapes text
#   gslides.sh geom       PRESENTATION_ID SLIDE_INDEX   # objectId + x/y/w/h + text
#
# set-text / set-cell replace text in place via insert-then-delete, so the
# first character's style (bold/colour/size) is inherited by the new text.
# ROW/COL are 0-based (row 0 = header). SLIDE_INDEX is 0-based.
#
# Examples:
#   gslides.sh info 1oAh...41QA
#   gslides.sh text 1oAh...41QA                     # All slides text
#   gslides.sh text 1oAh...41QA 1                    # Slide 2 text (0-indexed)
#   gslides.sh slides 1oAh...41QA                    # List slide IDs
#   gslides.sh slide 1oAh...41QA 1                   # Full JSON for slide 2
#   gslides.sh shapes 1oAh...41QA 1                  # List shape IDs + text for slide 2
#   gslides.sh replace 1oAh...41QA "OLD" "NEW"       # Global text replace
#   gslides.sh set-text 1oAh...41QA p2_i49 "42%"     # Set text in specific shape
#   gslides.sh set-font 1oAh...41QA "Open Sans"      # Set font on ALL text shapes (incl. bullet glyphs)
#   gslides.sh set-font 1oAh...41QA "Open Sans" p2_i49  # Set font on one specific shape
#   gslides.sh duplicate 1oAh...41QA p2              # Duplicate slide by objectId
#   gslides.sh delete 1oAh...41QA p2                 # Delete slide by objectId
#   gslides.sh batch 1oAh...41QA '[{...}]'           # Raw batchUpdate requests

set -euo pipefail

# Token resolution: explicit TOKEN_PATH wins; else GOOGLE_PROFILE -> ~/.config/google/<profile>/token.json
# (e.g. GOOGLE_PROFILE=nix); else the legacy mcp-google-sheets default.
if [ -z "${TOKEN_PATH:-}" ]; then
  # Account profile: GOOGLE_PROFILE env wins; else the first positional arg (nix, personal, …).
  [ -n "${GOOGLE_PROFILE:-}" ] || { GOOGLE_PROFILE="${1:?profile required as 1st arg (e.g. nix, personal) or set GOOGLE_PROFILE/TOKEN_PATH}"; shift; }
  export GOOGLE_PROFILE
  TOKEN_PATH="$HOME/.config/google/${GOOGLE_PROFILE}/token.json"
fi
API="https://slides.googleapis.com/v1/presentations"

# ── Token management (shared with gsheet.sh) ────────────────────

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

cmd_info() {
  local pid="$1"
  api_get "${API}/${pid}?fields=presentationId,title,pageSize,slides.objectId" | jq .
}

cmd_slides() {
  local pid="$1"
  api_get "${API}/${pid}?fields=slides.objectId" \
    | jq -r '.slides[] | .objectId'
}

cmd_slide() {
  local pid="$1" index="$2"
  api_get "${API}/${pid}?fields=slides" \
    | jq ".slides[${index}]"
}

cmd_text() {
  local pid="$1" index="${2:-all}"
  local data
  data=$(api_get "${API}/${pid}?fields=slides(objectId,pageElements(objectId,shape(shapeType,text(textElements(textRun(content))))))")

  if [[ "$index" == "all" ]]; then
    echo "$data" | jq -r '
      .slides | to_entries[] |
      "=== Slide \(.key) [\(.value.objectId)] ===",
      (.value.pageElements[]? |
        .shape?.text?.textElements[]? |
        .textRun?.content? // empty),
      ""'
  else
    echo "$data" | jq -r "
      .slides[${index}] |
      \"=== Slide ${index} [\\(.objectId)] ===\",
      (.pageElements[]? |
        .shape?.text?.textElements[]? |
        .textRun?.content? // empty)"
  fi
}

cmd_replace() {
  local pid="$1" old_text="$2" new_text="$3"
  local body
  body=$(jq -n --arg old "$old_text" --arg new "$new_text" '{
    requests: [{
      replaceAllText: {
        containsText: { text: $old, matchCase: true },
        replaceText: $new
      }
    }]
  }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq .
}

cmd_duplicate() {
  local pid="$1" slide_id="$2"
  local body
  body=$(jq -n --arg sid "$slide_id" '{
    requests: [{
      duplicateObject: { objectId: $sid }
    }]
  }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq .
}

cmd_delete() {
  local pid="$1" slide_id="$2"
  local body
  body=$(jq -n --arg sid "$slide_id" '{
    requests: [{
      deleteObject: { objectId: $sid }
    }]
  }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq .
}

# Replace a shape's text, preserving the existing style: insert the new text at
# index 0 (it inherits the style of the old first char), then delete the old
# trailing text. (delete-all-then-insert would reset to default formatting.)
cmd_set_text() {
  local pid="$1" shape_id="$2" new_text="$3"
  local body
  body=$(jq -n --arg sid "$shape_id" --arg txt "$new_text" '{
    requests: [
      { insertText: { objectId: $sid, text: $txt, insertionIndex: 0 } },
      { deleteText: { objectId: $sid, textRange: { type: "FROM_START_INDEX", startIndex: ($txt | length) } } }
    ]
  }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq .
}

# Replace a table cell's text in place, preserving style (same insert-then-delete).
cmd_set_cell() {
  local pid="$1" tbl="$2" row="$3" col="$4" new_text="$5"
  local body
  body=$(jq -n --arg tid "$tbl" --argjson row "$row" --argjson col "$col" --arg txt "$new_text" '{
    requests: [
      { insertText: { objectId: $tid, cellLocation: {rowIndex:$row, columnIndex:$col}, text: $txt, insertionIndex: 0 } },
      { deleteText: { objectId: $tid, cellLocation: {rowIndex:$row, columnIndex:$col}, textRange: { type: "FROM_START_INDEX", startIndex: ($txt | length) } } }
    ]
  }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq .
}

# Readable dump of a slide: every table (cells, pipe-joined) + every text shape.
cmd_dump() {
  local pid="$1" index="$2"
  api_get "${API}/${pid}?fields=slides(objectId,pageElements(objectId,shape(text(textElements(textRun(content)))),table(rows,columns,tableRows(tableCells(text(textElements(textRun(content))))))))" \
    | jq -r --argjson idx "$index" '
      .slides[$idx] |
      "slide \(.objectId)",
      (.pageElements[]? |
        if has("table") then
          "[TABLE \(.objectId) \(.table.rows)x\(.table.columns)]",
          (.table.tableRows[] | "  | " +
            ([.tableCells[] | [.text.textElements[]?.textRun.content // ""] | (add // "") | gsub("\n";" ") | gsub("^ +| +$";"")] | join(" | ")))
        elif has("shape") then
          (([.shape.text.textElements[]?.textRun.content // ""] | (add // "")) | gsub("\n";" / ")) as $t |
          if ($t | gsub(" ";"") | length) > 0 then "[\(.objectId)] \($t)" else empty end
        else empty end)'
}

# Geometry of a slide: objectId + x/y/w/h (EMU) + text, sorted top-to-bottom.
cmd_geom() {
  local pid="$1" index="$2"
  api_get "${API}/${pid}?fields=slides(pageElements(objectId,size,transform,shape(text(textElements(textRun(content)))),table(rows,columns)))" \
    | jq -r --argjson idx "$index" '
      [ .slides[$idx].pageElements[]? | {
          y: ((.transform.translateY // 0) | round),
          x: ((.transform.translateX // 0) | round),
          w: (((.size.width.magnitude // 0) * (.transform.scaleX // 1)) | round),
          h: (((.size.height.magnitude // 0) * (.transform.scaleY // 1)) | round),
          id: .objectId,
          t: ( if has("table") then "<TABLE \(.table.rows)x\(.table.columns)>"
               else (([.shape.text.textElements[]?.textRun.content // ""] | (add // "")) | gsub("\n";" ") | .[0:34]) end )
        } ] | sort_by(.y) | .[] |
      "\(.y)\t\(.x)\t\(.w)\t\(.h)\t\(.id)\t\(if (.t|length)==0 then "EMPTY" else .t end)"'
}

cmd_shapes() {
  local pid="$1" index="$2"
  api_get "${API}/${pid}?fields=slides(objectId,pageElements(objectId,shape(shapeType,text(textElements(textRun(content))))))" \
    | jq -r ".slides[${index}].pageElements[] | \"\(.objectId)\t\([.shape?.text?.textElements[]? | .textRun?.content? // empty] | join(\"\") | gsub(\"\\n\"; \"\") | .[:80])\""
}

cmd_batch() {
  local pid="$1" requests_json="$2"
  local body
  body=$(jq -n --argjson r "$requests_json" '{ requests: $r }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq .
}

# Apply a font family to text shapes. With no SHAPE_ID, applies to ALL text
# shapes across every slide. textRange:ALL covers the bullet glyph position
# (paragraph-start), so bullet glyphs render in the same font as the body.
# Both fontFamily and weightedFontFamily are set, since Slides preserves the
# older weightedFontFamily on render — both must match.
cmd_set_font() {
  local pid="$1" font="$2" shape_id="${3:-}"
  local requests body shape_ids

  if [[ -n "$shape_id" ]]; then
    requests=$(jq -n --arg sid "$shape_id" --arg f "$font" '[{
      updateTextStyle: {
        objectId: $sid,
        textRange: { type: "ALL" },
        style: {
          fontFamily: $f,
          weightedFontFamily: { fontFamily: $f, weight: 400 }
        },
        fields: "fontFamily,weightedFontFamily"
      }
    }]')
  else
    shape_ids=$(api_get "${API}/${pid}?fields=slides.pageElements(objectId,shape(text))" \
      | jq -r '[.slides[].pageElements[]? | select(.shape.text != null) | .objectId] | unique | .[]')

    if [[ -z "$shape_ids" ]]; then
      echo "ERROR: no text shapes found in presentation $pid" >&2
      return 1
    fi

    requests=$(echo "$shape_ids" | jq -R -s --arg f "$font" '
      split("\n") | map(select(length > 0)) | map({
        updateTextStyle: {
          objectId: .,
          textRange: { type: "ALL" },
          style: {
            fontFamily: $f,
            weightedFontFamily: { fontFamily: $f, weight: 400 }
          },
          fields: "fontFamily,weightedFontFamily"
        }
      })')
  fi

  body=$(jq -n --argjson r "$requests" '{ requests: $r }')
  api_post "${API}/${pid}:batchUpdate" "$body" | jq '{
    requestCount: (.replies | length)
  }'
}

# ── Main ──────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  head -25 "$0" | grep '^#' | sed 's/^# \?//'
  exit 1
fi

cmd="$1"; shift

case "$cmd" in
  info)      cmd_info "$@" ;;
  text)      cmd_text "$@" ;;
  slides)    cmd_slides "$@" ;;
  slide)     cmd_slide "$@" ;;
  shapes)    cmd_shapes "$@" ;;
  dump)      cmd_dump "$@" ;;
  geom)      cmd_geom "$@" ;;
  replace)   cmd_replace "$@" ;;
  set-text)  cmd_set_text "$@" ;;
  set-cell)  cmd_set_cell "$@" ;;
  set-font)  cmd_set_font "$@" ;;
  duplicate) cmd_duplicate "$@" ;;
  delete)    cmd_delete "$@" ;;
  batch)     cmd_batch "$@" ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Commands: info, text, slides, slide, shapes, dump, geom, replace, set-text, set-cell, set-font, duplicate, delete, batch" >&2
    exit 1
    ;;
esac
