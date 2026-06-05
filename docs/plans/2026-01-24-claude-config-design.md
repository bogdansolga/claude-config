# Claude Config Repository Design

**Date**: 2026-01-24

## Purpose

Shareable Claude Code configuration for consistent setup across machines, with secondary use as a team showcase/baseline.

## Structure

```
claude-config/
├── commands/
│   ├── git/      (catchup, commit, sync, cleanup)
│   ├── pr/       (checks, create, review-local, review, code-rabbit, merge)
│   └── quality/  (quick-fix, find-large-files)
├── scripts/
│   └── status-line.sh
├── config/
│   ├── config.json   (model, theme, editor)
│   └── settings.json (plugins, status line)
├── install.sh
└── README.md
```

## Command Naming Convention

Format: `category:action`

- `/git:catchup`, `/git:commit`, `/git:sync`, `/git:cleanup`
- `/pr:checks`, `/pr:create`, `/pr:review-local`, `/pr:review`, `/pr:code-rabbit`, `/pr:merge`
- `/quality:quick-fix`, `/quality:find-large-files`

## Installation

- Symlinks for commands/scripts (auto-update via git pull)
- Copies for config files (preserve user customizations)
- Backup existing commands before overwriting

## Sources

Commands consolidated from:
- `~/.claude/commands/` (global)
- `ave-ai-agent/.claude/commands/`
- `finances-manager/.claude/commands/`
- `ccpm/.claude/commands/`

Excluded:
- Work-specific commands (interview-prep)
- Obsolete workflow commands (implement-phase, research, plan, create-tasks)

## Plugins

- `superpowers@superpowers-marketplace`
- `frontend-design@claude-plugins-official`
- `ralph-loop@claude-plugins-official`
