---
command: handoff:create
description: Write a session-handoff doc so a fresh Claude Code session can pick up the work
---

# Create a session handoff

Write a self-contained handoff document capturing the current state of this Claude Code session, so a fresh session (or a human) can resume the work cold.

`$ARGUMENTS`, if provided, is a short hint about what to emphasise (e.g. a focus area, a caveat to highlight, or a target path). Otherwise infer everything from the conversation + repo state.

## Steps

1. **Gather repo state** (run these):
   - `git status --short` — uncommitted + untracked files
   - `git log --oneline -15` — recent commits
   - `git branch --show-current` and `git log --oneline @{u}.. 2>/dev/null` — commits ahead of upstream (if any)
   - `git diff --stat` and `git diff --stat --staged` — what's changed but not committed
   - If a `package.json`/`Cargo.toml`/`go.mod` etc. exists, note the verify/test/build command(s).

2. **Reconstruct the session story** from the conversation:
   - What was the goal? What was actually done? What's half-done or deliberately deferred?
   - Decisions made and *why* (especially non-obvious ones — these are the most valuable thing in a handoff).
   - Things that bit you / gotchas discovered (failed approaches, environment quirks, hidden constraints).
   - Any in-flight background tasks, running processes, temporary state (e.g. added swap, opened tunnels) — and whether they were cleaned up.

3. **Decide the output path** (priority order — handoffs live *inside the project repo* alongside the code they document):
   - If `$ARGUMENTS` looks like a path, use it.
   - **Default:** `<project-root>/docs/handoffs/<YYYY-MM-DD-HHMM>.md` (timestamped — never overwrite). `<project-root>` = git repo root if there is one, else cwd. `mkdir -p` as needed.
   - **In-place mode** — if the project already has a single rolling handoff doc (a `HANDOFF.md` at repo root, or a `docs/**/HANDOFF.md` the project's CLAUDE.md / README references as *the* state-snapshot), update **that** in place instead of writing a new file. Mention to the user which mode you picked (timestamped-new vs in-place-update).
   - Tell the user the path you chose.

4. **Write the handoff** using this structure (drop sections that don't apply; keep it tight — facts over prose):

   ```markdown
   # Session handoff — <project name> — <YYYY-MM-DD>

   **Branch:** <branch>  ·  **Updated:** <date/time>  ·  **Last commit:** <sha> <subject>
   If you were pointed at this file, read it fully before doing anything else.

   ## 1. Where we are
   <1–3 short paragraphs: what this work is, the current state, what's live/deployed if relevant.>

   ## 2. What this session did
   <Commit list (newest last) with a one-line summary each; then any uncommitted/in-progress work and its state.>

   ## 3. Open / next steps — ranked
   <Numbered list, easiest/highest-value first. Mark each [easy]/[medium]/[hard] and whether it's blocked on anything.>

   ## 4. Decisions & rationale
   <The non-obvious calls and *why*. This is the part that rots if not written down.>

   ## 5. Gotchas / lessons learned
   <Failed approaches, env quirks, hidden constraints, "don't do X because Y".>

   ## 6. State-check on entry
   <The exact commands a fresh session should run first to confirm this handoff is still accurate — git log, build/test, service health, etc. — plus the "healthy signals" to expect.>

   ## 7. Pointers
   <Key files (path:line where useful), other docs to read, external resources (dashboards, tickets, repos), credentials/access notes.>

   ## 8. Session metadata
   <Date; branch; whether the working tree is clean; how to access the DB / services; whether dev servers / tunnels / background jobs are running; anything else a resumer needs operationally.>
   ```

5. **Verify**: re-read the file you wrote; confirm a stranger could resume from it without the conversation. Then report the path and a 3–5 line summary of what's in it.

## Notes
- Do **not** put secrets in the handoff (passwords, tokens, full connection strings) — reference where they live instead.
- Do **not** commit the handoff unless the user asks. If they do, commit it per the host project's commit-message convention (check the project's CLAUDE.md / recent `git log` — many projects use `[feat]/[fix]/[chore]/[refactor]/[doc]` prefixes; some use Conventional Commits or freeform).
- If the conversation is thin (little actually happened), say so and write a short handoff rather than padding it.
- Since handoffs now live inside the project, consider whether to add `docs/handoffs/` to `.gitignore` for projects where you want handoffs ephemeral. For projects where the handoff history is valuable (debug logs, decision records), let them be tracked — that's the default.
