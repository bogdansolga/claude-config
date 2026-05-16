# Global rules

## Use rtk for token-heavy CLI calls

`rtk` is installed at `~/.local/bin/rtk` (on PATH) — a token-optimization proxy that filters/compresses CLI output before it reaches the LLM context.

**Rule:** when a shell command has an `rtk <subcommand>` wrapper, prefer the rtk form over the raw CLI. Run `rtk --help` once per session if unsure which wrappers exist.

Known wrappers (subject to change — `rtk --help` is authoritative):
`ls`, `tree`, `read`, `grep`, `find`, `diff`, `git`, `gh`, `glab`, `aws`, `psql`, `pnpm`, `docker`, `kubectl`, `wc`, `wget`, `log`, `json`, `env`, `deps`, `dotnet`, `jest`, `vitest`, `prisma`, `tsc`, `next`, `lint`, `err`, `test`, `smart`, `summary`.

**Don't use rtk when:** the command has no wrapper, the user explicitly asks for raw output, or a dedicated harness tool (Read, Edit, Grep, Glob) is the better fit — those bypass the shell and rtk doesn't apply.

`rtk gain` shows the running savings ledger.

@RTK.md
