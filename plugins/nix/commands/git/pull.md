---
description: Pull from a remote using the N-iX SSH key (~/.ssh/nix). Use for N-iX private repos.
---
# Git Pull with N-iX SSH Key

Pull using the nix key:
```bash
GIT_SSH_COMMAND="ssh -i ~/.ssh/nix -o IdentitiesOnly=yes" git pull "$@"
```
Report updated files or "Already up to date"; handle merge conflicts if any.
