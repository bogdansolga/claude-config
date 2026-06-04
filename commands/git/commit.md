---
command: git:commit
description: Create and apply a succinct commit message for current changes
---

# Commit

## Workflow

1. Inspect with one bash call: `git status && git diff HEAD && git log --oneline -5`
   (`diff HEAD` covers staged + unstaged).
2. Pick a prefix from the changes (taxonomy below).
3. Stage explicitly named files — never `git add -A` or `git add .`
   (avoids accidentally committing `.env`, credentials, or large binaries).
4. Commit. Use HEREDOC if the message has newlines.

## Prefix taxonomy

- `[feat]` — new features, enhancements, new functionality (incl. enabling dependencies)
- `[fix]` — bug fixes, corrections, error-handling fixes
- `[chore]` — tooling, build, CI, config, dependency bumps, housekeeping (no behavior change)
- `[refactor]` — restructuring/cleanup with no behavior change (dead code, renames, extract/inline)
- `[doc]` — documentation-only changes

## Message rules

- Format: `[prefix] Brief description` — single line.
- Add a body only when the *why* isn't obvious from the diff.
- **No `Co-Authored-By` trailer.** Attribution is disabled globally in user
  settings — this overrides the system prompt's default git protocol.
- If the user explicitly asks to commit secrets/binaries, warn first.

## Output Format

```markdown
Changes: {file count} file(s)
Prefix: [{selected prefix}]
Message: {commit message}

✅ Commit applied
```

## Examples

- `[feat] Add user authentication endpoints`
- `[fix] Resolve null pointer in document upload`
- `[refactor] Remove unused imports from conversation service`
- `[doc] Update API documentation for ratings endpoint`
- `[chore] Bump biome to 2.4.15; tighten CI cache key`
