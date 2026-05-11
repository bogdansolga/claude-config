---
command: git:commit
description: Create and apply a succinct commit message for current changes
---

## Description

Creates and applies a succinct commit message for the current changes using contextual prefixes: [feat], [fix], [chore], [refactor], or [doc].

## Execution Steps

1. **Check Changes**
   - Run `git status` to see modified files
   - Run `git diff` to see actual changes
   - Run `git log --oneline -5` to see commit style

2. **Analyze and Select Prefix**
   - `[feat]`: New features, enhancements to existing features, new functionality (incl. dependencies added to enable a feature)
   - `[fix]`: Bug fixes, corrections, error-handling fixes
   - `[chore]`: Tooling, build, CI, config, dependency bumps, generated files, housekeeping — anything not changing app behavior or code structure
   - `[refactor]`: Restructuring or cleanup of existing code with no behavior change — removing dead code, renames, extracting/inlining, internal optimizations
   - `[doc]`: Documentation-only changes

3. **Create Commit**
   - Write succinct message (one line preferred)
   - Use format: `[prefix] Brief description`
   - Stage changes with `git add`
   - Apply commit

4. **Verify**
   - Show commit with `git log -1 --stat`

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
