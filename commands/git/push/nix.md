---
command: git:push:nix
description: Push the current branch using the n-ix work Git identity (github-nix SSH alias / bsolga)
---

# Push (n-ix identity)

Push the **current branch** to `origin` using the **n-ix work Git identity**, not the personal
GitHub account. Use this for repos under n-ix orgs (e.g. `N-iX-GenAI-Value-LAB/*`) where a plain
`git push` fails with **"Repository not found"** — that error means the *personal* key answered and
has no access to the private repo.

## Why this exists — two identities on one machine

| Identity | SSH alias | Account | Key |
|----------|-----------|---------|-----|
| Personal | `github.com` (default) | `bogdansolga` | `~/.ssh/id_*` |
| n-ix work | `github-nix` | `bsolga` | `~/.ssh/nix` |

A `git@github.com:` remote resolves to the **personal** key. Routing `origin` through the
`github-nix` SSH alias (`HostName github.com`, `IdentityFile ~/.ssh/nix`, `IdentitiesOnly yes`)
selects the **n-ix** key instead.

## Steps

1. **Sanity-check the alias** (optional): `ssh -T git@github-nix` → expect `Hi bsolga!`.
2. **Normalize `origin` to the alias, only if needed:**
   - `git remote get-url origin`
   - If it's `git@github.com:<org>/<repo>.git` or `https://github.com/<org>/<repo>.git`, rewrite to
     the alias form (keep `.git`, drop any trailing `/`):
     `git remote set-url origin git@github-nix:<org>/<repo>.git`
   - If it already starts with `git@github-nix:`, leave it untouched.
3. **Push the current branch, setting upstream when missing:**
   `git push --set-upstream origin "$(git branch --show-current)"`
   (harmless if the upstream already exists; it still pushes.)
4. **Report:** the pushed branch, ahead/behind result, and the PR-create URL GitHub prints.

## Notes

- The rewrite is **durable** (per-repo git config) and **idempotent** — after the first run, plain
  `git push` / `git pull` from this repo keep using the n-ix identity. Companion: `git:pull:nix`.
- Only touch `origin`; leave other remotes alone.
- **Push identity ≠ commit author.** If the repo also needs your n-ix *email* on the commit, that's
  `git config user.email …` + `git commit --amend --reset-author` — this command does not change it.
