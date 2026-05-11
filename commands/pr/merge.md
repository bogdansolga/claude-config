---
command: pr:merge
description: Merge PR with squash, combining commit messages for catchup context
---

## Description

Merges the current branch's PR with squash, combining all commit messages into a single optimized commit message designed for use with the `/catchup` command.

## Execution Steps

1. **Verify PR Status**
   - Run `git branch --show-current` to get current branch
   - Run `gh pr view --json number,title,state,mergeable` to check PR status
   - Abort if PR is not mergeable or doesn't exist

2. **Gather Commit History**
   - Run `git log master..HEAD --oneline` to see all commits
   - Run `git log master..HEAD --format="%s%n%b"` to get commit messages with bodies
   - Run `git diff master...HEAD --stat` to see files changed

3. **Detect PRD Phase**
   - Check if branch name contains phase reference (e.g., `phase2`, `phase-2`, `p2`)
   - Extract phase number if present (e.g., "Phase 2" from `feature/saltedge-phase2-connect-flow`)
   - Look for corresponding PRD files in `docs/plans/` for context

4. **Determine Prefix**
   - Analyze commit messages and changes to determine type (same scheme as `/git:commit`):
     - `[feat]`: New features, enhancements, new functionality (incl. feature-enabling dependencies)
     - `[fix]`: Bug fixes, corrections, error-handling fixes
     - `[chore]`: Tooling, build, CI, config, dependency bumps, housekeeping
     - `[refactor]`: Restructuring / cleanup of existing code with no behavior change
     - `[doc]`: Documentation-only changes
   - Default to `[feat]` for mixed or unclear changes

5. **Generate Optimized Commit Message**
   - Get PR title from `gh pr view --json title`
   - Create title using format: `[prefix] PR_TITLE (#PR_NUMBER)`
   - If phase detected, ensure PR title includes phase (e.g., "Feature Name Phase N - Description")
   - Keep total title length reasonable (aim for ~72 chars when possible)
   - Add a blank line
   - Add a structured body with:
     - **Phase** (if applicable): Reference to PRD phase
     - **Purpose**: One sentence explaining what and why
     - **Changes**: Bullet list of key changes (from commit messages)
     - **Files**: Group changed files by area/purpose
   - Format for maximum `/catchup` usefulness

6. **Execute Squash Merge**
   - Extract first line from commit message as subject
   - Use `gh pr merge --squash --subject "FIRST_LINE" --body "REST_OF_MESSAGE"`
   - Do NOT include co-author footer
   - Do NOT include "Generated with Claude Code" footer

7. **Cleanup**
   - Run `git checkout master`
   - Run `git pull`
   - Delete the merged branch (locally and remotely)

## Commit Message Format

### Without Phase
```
[prefix] Brief summary of what was accomplished (#123)

**Purpose:** Why this change was made and what problem it solves.

**Changes:**
- Change 1 (from commit messages)
- Change 2
- Change 3

**Files:**
- area1/: file1, file2 - description
- area2/: file3 - description
```

### With Phase (from PRD)
```
[prefix] Feature Name Phase N - Descriptive title from PR (#123)

**Phase:** Phase N of [Feature Name] implementation

**Purpose:** Why this change was made and what problem it solves.

**Changes:**
- Change 1 (from commit messages)
- Change 2
- Change 3

**Files:**
- area1/: file1, file2 - description
- area2/: file3 - description
```

## Example Output

### Standard PR (no phase)
```markdown
Branch: docker-build-improvements
PR: #123 (mergeable)
Commits: 6 → 1 (squash)
Prefix: [feat]

Commit message:
[feat] Docker build security and workflow improvements (#123)

**Purpose:** Enhance Docker build security and improve CI workflow reliability.

**Changes:**
- Add multi-stage build for smaller image
- Configure non-root user in container
- Add health check endpoint
- Update GitHub Actions workflow

**Files:**
- docker/: Dockerfile, docker-compose.yml - build configuration
- .github/: ci.yml - workflow updates
- src/api/: health.ts - health check endpoint

✅ PR merged and squashed
```

### Phase-based PR
```markdown
Branch: feature/auth-phase2-oauth-flow
PR: #32 (mergeable)
Commits: 12 → 1 (squash)
Phase detected: Phase 2
Prefix: [feat]

Commit message:
[feat] Auth Phase 2 - OAuth Flow (#32)

**Phase:** Phase 2 of Authentication implementation

**Purpose:** Enable OAuth login flow with multiple providers.

**Changes:**
- Implement OAuth connect flow
- Add provider configuration
- Create callback endpoints
- Build provider selector UI

**Files:**
- src/lib/auth/: OAuth client, providers
- src/app/api/auth/: callback endpoints
- src/components/: provider selector

✅ PR merged and squashed
```

## Notes

- Requires `gh` CLI to be installed and authenticated
- The command will fail if the PR is not approved or has merge conflicts
- Does not force push or modify history of the source branch
- After merge, source branch can be safely deleted
