#!/usr/bin/env bash
# jira.sh — Jira Cloud CLI via REST API v2
# Reuses the same Atlassian API token as confluence.sh (basic auth: email:token).
#
# Usage:
#   jira.sh get         ISSUE_KEY
#   jira.sh get-text    ISSUE_KEY
#   jira.sh search      "JQL query"
#   jira.sh create      PROJECT_KEY ISSUE_TYPE SUMMARY DESC_FILE [--parent PARENT_KEY] [--due YYYY-MM-DD] [--label L]...
#   jira.sh link        BLOCKER_KEY BLOCKED_KEY [LINK_TYPE]   # BLOCKER blocks BLOCKED (default "Blocks")
#   jira.sh attach      ISSUE_KEY FILE
#   jira.sh comment     ISSUE_KEY "body text"
#   jira.sh label-add   ISSUE_KEY LABEL [LABEL...]            # add label(s) to an issue
#   jira.sh children    EPIC_KEY                              # keys in an epic's hierarchy (epic+children+sub-tasks)
#   jira.sh link-types                                        # list configured issue-link types
#   jira.sh types       PROJECT_KEY                           # list creatable issue types for a project
#
# Examples:
#   jira.sh get VVLK-125
#   jira.sh get-text VVLK-125
#   jira.sh search "project = VVLK AND statusCategory != Done ORDER BY created DESC"
#   jira.sh create VVLK Task "D3 — authoring/trigger surface" /tmp/desc.txt
#   jira.sh link VVLK-201 VVLK-200            # VVLK-201 blocks VVLK-200 (VVLK-200 depends on VVLK-201)
#   jira.sh attach VVLK-200 docs/reviews/latest/d3-authoring-trigger-surface.md
#
# Environment (searched upward for a .env, like confluence.sh):
#   JIRA_URL         — e.g. https://n-ix-nordic.atlassian.net   (falls back to CONFLUENCE_URL minus /wiki)
#   JIRA_USERNAME    — e.g. bsolga@n-ix.com                     (falls back to CONFLUENCE_USERNAME)
#   JIRA_API_TOKEN   — Atlassian API token                      (falls back to CONFLUENCE_API_TOKEN)

set -euo pipefail

# ── Load .env (search upward from script dir, then CWD) ────────────

load_env() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.env" ]]; then
      # shellcheck disable=SC1091
      set -a; source "$dir/.env"; set +a
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

load_env "$(cd "$(dirname "$0")" && pwd)" 2>/dev/null || \
load_env "$(pwd)" 2>/dev/null || true

# Accept common alternate var names, then fall back to the Confluence
# credentials (same Atlassian instance + token).
JIRA_URL="${JIRA_URL:-${JIRA_BASE_URL:-${CONFLUENCE_URL:-}}}"
JIRA_URL="${JIRA_URL%/wiki}"           # strip Confluence's /wiki suffix if present
JIRA_USERNAME="${JIRA_USERNAME:-${JIRA_EMAIL:-${CONFLUENCE_USERNAME:-}}}"
JIRA_API_TOKEN="${JIRA_API_TOKEN:-${CONFLUENCE_API_TOKEN:-}}"

: "${JIRA_URL:?Set JIRA_URL (e.g. https://your-domain.atlassian.net) or CONFLUENCE_URL}"
: "${JIRA_USERNAME:?Set JIRA_USERNAME (e.g. you@company.com) or CONFLUENCE_USERNAME}"
: "${JIRA_API_TOKEN:?Set JIRA_API_TOKEN or CONFLUENCE_API_TOKEN}"

JIRA_URL="${JIRA_URL%/}"               # strip trailing slash (avoids //rest/...)
API="${JIRA_URL}/rest/api/2"
API3="${JIRA_URL}/rest/api/3"
AUTH="${JIRA_USERNAME}:${JIRA_API_TOKEN}"

# ── API helpers ───────────────────────────────────────────────────

check_http() {
  local response="$1" url="$2"
  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: HTTP $http_code from $url" >&2
    echo "$body" | jq -r '.errorMessages[]? , (.errors // {} | to_entries[]? | "\(.key): \(.value)")' >&2 2>/dev/null || echo "$body" >&2
    return 1
  fi
  echo "$body"
}

api_get() {
  local url="$1"
  check_http "$(curl -s -w $'\n%{http_code}' -u "$AUTH" -H "Accept: application/json" "$url")" "$url"
}

api_post() {
  local url="$1" body="$2"
  check_http "$(curl -s -w $'\n%{http_code}' -X POST -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "$body" "$url")" "$url"
}

api_put() {
  local url="$1" body="$2"
  check_http "$(curl -s -w $'\n%{http_code}' -X PUT -u "$AUTH" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "$body" "$url")" "$url"
}

api_delete() {
  local url="$1"
  check_http "$(curl -s -w $'\n%{http_code}' -X DELETE -u "$AUTH" -H "Accept: application/json" "$url")" "$url"
}

# ── Commands ──────────────────────────────────────────────────────

cmd_get() {
  local key="$1"
  api_get "${API}/issue/${key}" \
    | jq '{key: .key, type: .fields.issuetype.name, status: .fields.status.name,
           summary: .fields.summary, assignee: .fields.assignee.displayName,
           labels: .fields.labels, duedate: .fields.duedate,
           project: .fields.project.key, parent: .fields.parent.key,
           links: [.fields.issuelinks[]? |
                   if .inwardIssue then "\(.type.outward) \(.inwardIssue.key)"
                   else "\(.type.inward) \(.outwardIssue.key)" end]}'
}

cmd_get_text() {
  local key="$1"
  api_get "${API}/issue/${key}" \
    | jq -r '"# " + .key + " — " + .fields.summary,
             "Type: " + .fields.issuetype.name + " | Status: " + .fields.status.name,
             "", (.fields.description // "(no description)")'
}

cmd_search() {
  local jql="$1"
  local payload
  payload=$(jq -n --arg jql "$jql" '{jql: $jql, maxResults: 100,
    fields: ["summary","status","issuetype","labels"]}')
  # v2 /search was removed (HTTP 410); use v3 /search/jql
  api_post "${API3}/search/jql" "$payload" \
    | jq -r '.issues[] | "\(.key)  [\(.fields.issuetype.name)/\(.fields.status.name)]  \(.fields.summary)  labels=\(.fields.labels)"'
}

# Print just the issue keys returned by a JQL (one per line)
search_keys() {
  local jql="$1"
  local payload
  payload=$(jq -n --arg jql "$jql" '{jql: $jql, maxResults: 100, fields: ["key"]}')
  api_post "${API3}/search/jql" "$payload" | jq -r '.issues[].key'
}

cmd_label_add() {
  local key="$1"; shift
  local ops="[]"
  for lbl in "$@"; do
    ops=$(echo "$ops" | jq --arg l "$lbl" '. + [{add: $l}]')
  done
  api_put "${API3}/issue/${key}" "$(jq -n --argjson ops "$ops" '{update: {labels: $ops}}')" >/dev/null \
    && echo "labels added to ${key}: $*"
}

# Every issue in an Epic's hierarchy: the epic, its children, and their sub-tasks.
cmd_children() {
  local epic="$1"
  { echo "$epic"
    local kids; kids=$(search_keys "parent = ${epic}")
    echo "$kids"
    for k in $kids; do search_keys "parent = ${k}"; done
  } | awk 'NF' | sort -u
}

cmd_create() {
  local project="$1" itype="$2" summary="$3" desc_file="$4"; shift 4
  local parent="" due="" labels_json="[]"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent) parent="$2"; shift 2 ;;
      --due)    due="$2"; shift 2 ;;          # YYYY-MM-DD
      --label)  labels_json=$(echo "$labels_json" | jq --arg l "$2" '. + [$l]'); shift 2 ;;
      *) echo "Unknown create option: $1" >&2; exit 1 ;;
    esac
  done

  local description
  description=$(cat "$desc_file")

  local fields
  fields=$(jq -n \
    --arg project "$project" --arg itype "$itype" \
    --arg summary "$summary" --arg description "$description" \
    --argjson labels "$labels_json" \
    '{project: {key: $project}, issuetype: {name: $itype},
      summary: $summary, description: $description}
     + (if ($labels | length) > 0 then {labels: $labels} else {} end)')

  if [[ -n "$parent" ]]; then
    fields=$(echo "$fields" | jq --arg p "$parent" '. + {parent: {key: $p}}')
  fi
  if [[ -n "$due" ]]; then
    fields=$(echo "$fields" | jq --arg d "$due" '. + {duedate: $d}')
  fi

  api_post "${API}/issue" "$(jq -n --argjson f "$fields" '{fields: $f}')" \
    | jq -r --arg base "$JIRA_URL" '"created \(.key)  \($base)/browse/\(.key)"'
}

# BLOCKER blocks BLOCKED  ⇒  BLOCKED "is blocked by" / depends on BLOCKER
cmd_link() {
  local blocker="$1" blocked="$2" ltype="${3:-Blocks}"
  local payload
  payload=$(jq -n --arg t "$ltype" --arg out "$blocker" --arg in "$blocked" \
    '{type: {name: $t}, outwardIssue: {key: $out}, inwardIssue: {key: $in}}')
  api_post "${API}/issueLink" "$payload" >/dev/null \
    && echo "linked: ${blocker} ${ltype} → ${blocked}  (${blocked} depends on ${blocker})"
}

# Remove the link between two issues (any direction)
cmd_unlink() {
  local a="$1" b="$2"
  local id
  id=$(api_get "${API}/issue/${a}?fields=issuelinks" \
    | jq -r --arg b "$b" '.fields.issuelinks[] | select((.inwardIssue.key==$b) or (.outwardIssue.key==$b)) | .id' | head -1)
  [[ -z "$id" || "$id" == "null" ]] && { echo "no link found between ${a} and ${b}" >&2; return 1; }
  api_delete "${API}/issueLink/${id}" >/dev/null && echo "unlinked ${a} ⇹ ${b} (link ${id})"
}

cmd_attach() {
  local key="$1" file="$2"
  local url="${API}/issue/${key}/attachments"
  local response
  response=$(curl -s -w $'\n%{http_code}' -X POST -u "$AUTH" \
    -H "X-Atlassian-Token: no-check" -F "file=@${file}" "$url")
  check_http "$response" "$url" \
    | jq -r '.[] | "attached \(.filename) (\(.size) bytes) to '"$key"'"'
}

cmd_comment() {
  local key="$1" body="$2"
  api_post "${API}/issue/${key}/comment" "$(jq -n --arg b "$body" '{body: $b}')" \
    | jq -r '"commented on '"$key"' (id \(.id))"'
}

cmd_set_desc() {
  local key="$1" desc_file="$2"
  local desc; desc=$(cat "$desc_file")
  api_put "${API}/issue/${key}" "$(jq -n --arg d "$desc" '{fields: {description: $d}}')" >/dev/null \
    && echo "description updated on ${key}"
}

cmd_set_due() {
  local key="$1" due="$2"
  api_put "${API}/issue/${key}" "$(jq -n --arg d "$due" '{fields: {duedate: $d}}')" >/dev/null \
    && echo "duedate ${due} set on ${key}"
}

cmd_weblink() {
  local key="$1" url="$2" title="${3:-$url}"
  api_post "${API}/issue/${key}/remotelink" \
    "$(jq -n --arg u "$url" --arg t "$title" '{object: {url: $u, title: $t}}')" \
    | jq -r '"web link added to '"$key"' (id \(.id))"'
}

cmd_link_types() {
  api_get "${API}/issueLinkType" | jq -r '.issueLinkTypes[] | "\(.name):  outward=\"\(.outward)\"  inward=\"\(.inward)\""'
}

cmd_types() {
  local project="$1"
  api_get "${API}/issue/createmeta?projectKeys=${project}&expand=projects.issuetypes" \
    | jq -r '.projects[].issuetypes[] | "\(.name)\(if .subtask then " (subtask)" else "" end)"'
}

# ── Main ──────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  head -32 "$0" | grep '^#' | sed 's/^# \?//'
  exit 1
fi

cmd="$1"; shift
case "$cmd" in
  get)        cmd_get "$@" ;;
  get-text)   cmd_get_text "$@" ;;
  search)     cmd_search "$@" ;;
  create)     cmd_create "$@" ;;
  link)       cmd_link "$@" ;;
  unlink)     cmd_unlink "$@" ;;
  attach)     cmd_attach "$@" ;;
  comment)    cmd_comment "$@" ;;
  set-desc)   cmd_set_desc "$@" ;;
  set-due)    cmd_set_due "$@" ;;
  label-add)  cmd_label_add "$@" ;;
  weblink)    cmd_weblink "$@" ;;
  children)   cmd_children "$@" ;;
  link-types) cmd_link_types "$@" ;;
  types)      cmd_types "$@" ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Commands: get, get-text, search, create, link, attach, comment, label-add, children, link-types, types" >&2
    exit 1
    ;;
esac
