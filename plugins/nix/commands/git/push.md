---
description: Push to a remote using the N-iX SSH identity (github-nix host alias). Use for N-iX (n-ix-nordic / private) repos.
---
# Git Push with N-iX SSH Key

Push using the nix identity via the `github-nix` host alias in `~/.ssh/config`. The remote URL must be `git@github-nix:ORG/REPO.git` (if not, set it first).

## Steps
1. Push: `git push "$@"`
2. Report success/failure. If upstream isn't set, suggest `git push -u origin <branch>`.
