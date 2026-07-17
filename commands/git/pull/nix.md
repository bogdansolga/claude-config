---
command: git:pull:nix
description: Pull the current branch using the n-ix work Git identity (github-nix SSH alias / bsolga)
---

# Pull (n-ix identity)

Fetch and integrate `origin` for the **current branch** using the **n-ix work Git identity**, not
the personal GitHub account. Read-direction companion to `git:push:nix` — same remote-normalization,
same reason.

## Why this exists — two identities on one machine

| Identity | SSH alias | Account | Key |
|----------|-----------|---------|-----|
| Personal | `github.com` (default) | `bogdansolga` | `~/.ssh/id_*` |
| n-ix work | `github-nix` | `bsolga` | `~/.ssh/nix` |

A `git@github.com:` remote resolves to the **personal** key, which can't read private n-ix repos
(`fatal: Could not read from remote repository`). The `github-nix` alias selects `~/.ssh/nix`.

## Steps

1. **Normalize `origin` to the alias, only if needed** (identical to `git:push:nix` step 2):
   - `git remote get-url origin`; if it's a `git@github.com:` / `https://github.com/` URL, rewrite to
     `git remote set-url origin git@github-nix:<org>/<repo>.git`; if already `git@github-nix:`, leave it.
2. **Pull the current branch, fast-forward only:**
   `git pull --ff-only origin "$(git branch --show-current)"`
   - `--ff-only` keeps history linear and **fails loudly on divergence** rather than auto-merging.
   - If it's rejected because local and remote diverged, **stop and report** — let the user pick
     rebase vs. merge; don't guess.
3. **Report:** commits pulled / files changed, or "already up to date".

## Notes

- The rewrite is **durable** and **idempotent** — after the first run, plain `git pull` from this repo
  keeps using the n-ix identity.
- Only touch `origin`; leave other remotes alone.
- Read-only against the remote — no local commits are created or amended.
