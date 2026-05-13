---
command: handoff:continue
description: Resume work from a session-handoff doc — read it, verify it's current, and pick up
---

# Continue from a session handoff

Resume a previous Claude Code session by reading its handoff document, verifying it still reflects reality, and surfacing where to pick up.

`$ARGUMENTS`, if provided, is the path to a specific handoff file (or a hint about which one). Otherwise locate the most recent one.

## Steps

1. **Find the handoff doc** (search in this order — handoffs live inside the project repo):
   - If `$ARGUMENTS` is a path, use it.
   - `<project-root>/docs/handoffs/*.md` — most recent by mtime (`<project-root>` = git repo root or cwd).
   - `<project-root>/HANDOFF.md` (the rolling-snapshot pattern some projects use).
   - `<project-root>/docs/**/HANDOFF.md` or `docs/**/*handoff*.md`.
   - If several plausible candidates exist, list them and ask which one — don't guess.
   - If none exists, say so and suggest running `/handoff:create` at the end of the previous session next time; then fall back to `/git:catchup`-style reconstruction (git log + status + diff).

2. **Read the handoff fully.** Then run its §"State-check on entry" commands (or, if it has none, run: `git log --oneline -15`, `git status --short`, plus any obvious build/test/health command for the stack).

3. **Reconcile handoff vs. reality**:
   - Did the "last commit" in the handoff match `git log`? (If HEAD moved past it, more happened after the handoff — flag it.)
   - Is the working tree state as described?
   - Do the "healthy signals" hold? If a service/health check is mentioned, probe it.
   - If anything in the handoff is now stale (renamed files, merged work, changed deploy state), note the discrepancy — trust what you observe now over what the doc says.

4. **Brief the user** — concise:
   - One paragraph: where things stand right now.
   - The top 1–3 open items from the handoff (re-ranked if reality changed).
   - Any discrepancies between the handoff and current state.
   - Then ask what they want to work on — or, if the handoff has a clear single next step and the user said to just continue, start on it.

5. **Do not** start making changes before step 4 unless the user explicitly said "just continue / pick up where you left off". Even then, state what you're about to do first.

## Notes
- Treat the handoff as a point-in-time snapshot, not gospel — verify load-bearing claims (a file/function it names may have been renamed or removed) before acting on them.
- If the handoff references durable user preferences or memory, honour them.
- If the handoff is thin or the trail has gone cold, say so plainly and propose how to re-establish context rather than improvising.
