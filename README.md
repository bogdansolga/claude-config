# claude-config

Central repository for Claude Code configuration - commands, skills, scripts, guardrails, and settings.

## Install

```bash
git clone git@github.com:bogdansolga/claude-config.git ~/.claude-config
~/.claude-config/sync-to-home.sh
```

Re-run `sync-to-home.sh` any time the repo changes; it is idempotent (the symlinks into `~/.claude/` get refreshed, `~/.claude-config/` copies updated). Pass `--dry-run` to preview.

## Commands

**Git**
- `/git:catchup` - what was I working on?
- `/git:commit` - commit with [feat]/[fix]/[chore]/[refactor]/[doc] prefix
- `/git:sync` - rebase on main
- `/git:cleanup` - delete merged branches

**PR**
- `/pr:checks` - lint, types, tests before PR
- `/pr:create` - push + create PR
- `/pr:review:local:review` - self-review diff
- `/pr:review:ci:review` - trigger Claude GitHub Action review
- `/pr:code-rabbit` - handle CodeRabbit comments
- `/pr:merge` - squash merge with structured message

**Quality**
- `/quality:quick-fix` - small fix, no heavy workflow
- `/quality:find-large-files` - find + split recommendations
- `/quality:simplify` - review for unnecessary complexity

**Next.js**
- `/nextjs:audit` - audit a Next.js project for performance and best practices
- `/nextjs:audit-all` - audit all Next.js projects in a directory
- `/nextjs:cache-strategy` - analyze and improve caching strategy
- `/nextjs:optimize` - apply Next.js optimizations (React Compiler, caching, Turbopack)
- `/nextjs:setup-agents` - set up AGENTS.md with version-matched docs
- `/nextjs:update-audit-script` - update the portable audit script

**Workflow**
- `/workflow:task-declarative` - define success criteria and let agent loop

**Handoff**
- `/handoff:create` - write a session-handoff doc for a fresh session to resume from
- `/handoff:continue` - resume work from a session-handoff doc

**PowerPoint (`.pptx` via OOXML)**
- `/ppt:read` - extract text from a `.pptx` without PowerPoint/LibreOffice
- `/ppt:update` - edit text in or append slides to a `.pptx`

**Other**
- `/marp-presentation` - create a Marp presentation

## Guardrails

### Biome Linter Rules (biome.jsonc)

| Rule | Level | Description |
|------|-------|-------------|
| `noConsole` | error | No console.log in production (except logger.ts) |
| `noExplicitAny` | error | No `any` type usage |
| `noImplicitAnyLet` | error | No implicit any in let declarations |
| `noEvolvingTypes` | error | No evolving types |
| `useAwait` | error | Async functions must use await |
| `noUselessConstructor` | error | No empty constructors |

### Git Pre-commit Hook (6 checks)

1. **Architecture hierarchy** - Pages → API Routes → Services → Repositories
2. **Schema locations** - Zod schemas in centralized location
3. **Deep architecture** - Repository purity, HOF patterns, auth
4. **TypeScript** - Type checking, unused code detection
5. **Biome linting** - Auto-fix + verify
6. **Code quality** - Secrets, HTTP_STATUS, file size, imports, TODOs

### Code Quality Script (scripts/check-code-quality.sh)

| Check | Type | Description |
|-------|------|-------------|
| Hardcoded secrets | BLOCKS | API keys, tokens, connection strings |
| HTTP_STATUS constants | BLOCKS | Use constants instead of magic numbers |
| File size (500 lines) | BLOCKS | Files must be under 500 lines |
| Import aliases | WARNS | Prefer `@/` over deep relative imports |
| TODO/FIXME comments | WARNS | Resolve before committing |

### Claude Code PreToolUse Hooks (claude-home/settings.json)

| Hook | Description |
|------|-------------|
| npm/npx/pnpm blocked | Must use bun/bunx instead |
| --no-verify blocked | Git hooks must run |
| Secrets in Write/Edit | Blocks hardcoded API keys, tokens |

## Skills

- `nextjs-developer.md` - Next.js development best practices
- `senior-typescript-developer.md` - TypeScript best practices

## Agents

- `typescript-reviewer.md` - Code review agent for TypeScript

## Plugins

Managed via `/plugins`. Configuration in `plugins/config.json`.

## Structure

```
claude-config/
├── README.md
├── sync-to-home.sh             # Idempotent installer / re-syncer
├── biome.jsonc                 # Project linter config
│
├── claude-home/                # → ~/.claude config files
│   ├── settings.json           # PreToolUse hooks, plugins, status line
│   ├── settings.local.json     # Local overrides
│   ├── config.json             # Model, theme, editor
│   ├── hooks.json              # Additional hooks
│   ├── CLAUDE.md               # User-level rules (e.g. rtk preference)
│   └── RTK.md                  # rtk (Rust Token Killer) reference
│
├── commands/                   # Slash commands (symlinked to ~/.claude/commands)
│   ├── git/                    # catchup, commit, sync, cleanup, pull, push
│   ├── pr/                     # checks, create, review, code-rabbit, merge
│   ├── nextjs/                 # audit, optimize, cache-strategy, setup-agents
│   ├── quality/                # quick-fix, find-large-files, simplify
│   ├── workflow/               # task-declarative
│   ├── handoff/                # create, continue
│   ├── ppt/                    # read, update
│   └── marp-presentation.md
│
├── agents/                     # Custom agents
│   └── typescript-reviewer.md
│
├── skills/                     # Custom skills
│   ├── nextjs-developer.md
│   └── senior-typescript-developer.md
│
├── output-styles/              # Custom output styles
│   └── direct-objective.md
│
├── plugins/                    # Plugin config (runtime caches gitignored)
│   └── config.json
│
├── scripts/                    # Standalone scripts
│   ├── check-code-quality.sh   # Code quality guardrails
│   ├── nextjs-audit.ts         # Portable Next.js audit script
│   ├── status-line.sh
│   ├── toggle-global-commands.sh
│   └── debug-status-input.sh   # Debug helper for the status line
│
├── docs/                       # Design / history docs
│
├── git-hooks/                  # Git hooks for projects
│   └── pre-commit              # 6-check pre-commit hook
│
└── next-docs/                  # Next.js reference documentation
```

## Sync to Home

After making changes in this repo, sync to home folders:

```bash
# Preview changes
./sync-to-home.sh --dry-run

# Apply changes
./sync-to-home.sh
```

This syncs:
- `claude-home/*` → `~/.claude/` (settings files)
- `commands/`, `scripts/`, `skills/`, `agents/`, `output-styles/`, `plugins/` → `~/.claude/` (as symlinks)
- `commands/`, `scripts/`, `skills/`, `next-docs/` → `~/.claude-config/` (copies, for backwards compatibility)

## Update

```bash
cd ~/.claude-config && git pull
```

Commands auto-update (symlinked). Configs don't (your customizations preserved).

## Uninstall

```bash
rm ~/.claude/commands ~/.claude/scripts ~/.claude/skills ~/.claude/agents ~/.claude/output-styles ~/.claude/plugins
# Restore backup if needed: mv ~/.claude/commands.bak.* ~/.claude/commands
```
