---
name: nix-jira
description: "Use when reading, creating, linking, labeling, attaching to, commenting on, or updating Jira issues in the N-iX Atlassian instance (n-ix-nordic.atlassian.net) — epics/stories/tasks, dependency links, web links, due dates, adapt/net-new tags. Driven by the jira.sh CLI (shell + curl + jq, no MCP, no install). Trigger on any VVLK-#### ticket work, an n-ix-nordic.atlassian.net URL, or an N-iX Jira request."
---

# nix-jira — Jira Cloud CLI for the N-iX Atlassian instance

Drive Jira via `jira.sh` — a shell/`curl`/`jq` CLI. No MCP, no install. Instance: `https://n-ix-nordic.atlassian.net`.

## Script

`~/.claude/skills/nix-jira/scripts/jira.sh` (bundled with this skill — self-contained shell/`curl`/`jq`). Set `J=~/.claude/skills/nix-jira/scripts/jira.sh` and call `"$J" <cmd>`.

## Auth

This skill ships its own token file: **`~/.claude/skills/nix-jira/.env`** (git-ignored, `chmod 600`) with `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`. **Source it into the environment in the SAME shell as the `jira.sh` call** — env vars don't persist across separate shell invocations:

```bash
set -a; source ~/.claude/skills/nix-jira/.env; set +a
J=~/.claude/skills/nix-jira/scripts/jira.sh
"$J" get VVLK-195
```

`jira.sh` reads these as env vars (`JIRA_BASE_URL`→base URL, `JIRA_EMAIL`→user, `JIRA_API_TOKEN`→token; `CONFLUENCE_*` also accepted), so this works **from any directory**. It also still falls back to any `.env` it finds by searching upward from the script dir / CWD (e.g. `~/Development/Projects/qa-server/.env`) if you don't source the skill file. Never print the token.

> If `~/.claude/skills/nix-jira/.env` is missing (fresh machine), recreate it with the three `JIRA_*` vars (Atlassian API token from id.atlassian.com). Keep it git-ignored — the skills dir is the `bogdansolga/.claude-config` repo.

## Commands

```bash
J=~/.claude/skills/nix-jira/scripts/jira.sh
"$J" get KEY                         # key/type/status/summary/parent/labels/duedate/links (human-readable)
"$J" get-text KEY                    # summary + description as plain text
"$J" search "JQL"                    # e.g. "project=VVLK AND labels=net-new ORDER BY key"
"$J" create PROJ TYPE "summary" DESCFILE [--parent KEY] [--due YYYY-MM-DD] [--label L]...
"$J" link BLOCKER BLOCKED [TYPE]     # default "Blocks": link A B → "A blocks B" (B depends on A)
"$J" unlink A B                      # remove the link between two issues (any direction)
"$J" set-desc KEY DESCFILE           # replace description (plain text)
"$J" set-due  KEY YYYY-MM-DD         # set due date
"$J" label-add KEY LABEL [LABEL...]  # additive (won't remove existing labels)
"$J" attach  KEY FILE                # attach a file
"$J" weblink KEY URL "title"         # add a web link (shows in the issue's Links)
"$J" comment KEY "text"
"$J" children EPIC_KEY               # all keys in an epic's hierarchy (epic + children + sub-tasks)
"$J" types PROJ                      # creatable issue types
"$J" link-types                      # configured issue-link types (Blocks, Relates, ...)
```

## Gotchas

- **Jira Cloud removed the v2 `/search` endpoint** (HTTP 410) → `jira.sh` already uses **v3 `/search/jql`**.
- **Labels cannot contain spaces** — use hyphens (`Agentic-Kit`, `net-new`, `adapt`).
- **Link direction:** `link BLOCKER BLOCKED` stores "BLOCKER blocks BLOCKED"; when you `get` an issue, direction is rendered as `blocks X` / `is blocked by X`.
- Descriptions/comments are plain text (REST v2), not ADF. Write the description to a temp file, pass its path to `create`/`set-desc`.
- **Confidentiality:** N-iX ticket content (ticket numbers, project, people) stays in N-iX repos — never commit it to personal GitHub repos. `jira.sh` itself (a generic tool, no secrets) is fine to version here; the token lives only in the git-ignored `.env`.
- After bulk label/link ops, verify via `get` (per-issue, authoritative) rather than `search` — the search index lags a few seconds behind writes.
