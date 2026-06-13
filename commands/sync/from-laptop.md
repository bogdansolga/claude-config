---
command: sync:from-laptop
description: Pull the current project from the laptop dev box back to this machine, resolving the laptop by hostname (no hardcoded IP)
---

# Sync project ← laptop

Pull the **current git project** **from the laptop** back to this machine — the inverse of `/sync:to-laptop`.

## Peer registry (resolve by hostname, never a hardcoded IP)

| Machine | mDNS hostname | ssh user |
|---------|---------------|----------|
| Laptop  | `NB01GAVL003` | `bsolga` |
| Studio  | `MacStudio`   | `bogdan` |

The remote peer for this command is the **laptop**. IPs change, so resolve it on the network instead of
hardcoding one. Override the whole target with the `LAPTOP_HOST` env var (`user@host`) to skip resolution.

⚠️ This **overwrites THIS machine's working tree** for the project with the laptop's copy (`--delete`
mirror). Local uncommitted changes here will be lost — guard before pulling.

## Steps

1. **Safety check — refuse to clobber uncommitted local work.** Inspect `git status -s` on this machine.
   If there are modified/staged tracked files (ignore untracked `.idea/`, `.DS_Store`, editor cruft), STOP
   and tell the user what would be lost — ask them to commit/stash or confirm explicitly before proceeding.
   Only continue automatically when the local tree is clean (or the user confirms).

2. **Resolve the laptop's address.** Try mDNS (`<hostname>.local`); only ask for an IP if that fails:

   ```bash
   USER_AT="bsolga"; HOSTNAME_SHORT="NB01GAVL003"
   if [ -n "${LAPTOP_HOST:-}" ]; then
     echo "RESOLVED: $LAPTOP_HOST"
   elif ping -c1 -t2 "$HOSTNAME_SHORT.local" >/dev/null 2>&1; then
     echo "RESOLVED: $USER_AT@$HOSTNAME_SHORT.local"
   else
     echo "UNRESOLVED: laptop '$HOSTNAME_SHORT' not found on the network via mDNS"
   fi
   ```

   - If it prints `RESOLVED: <host>`, use that as `HOST` below.
   - If it prints `UNRESOLVED`, **ask the user for the laptop's IP address**, then use `HOST="bsolga@<ip>"`.
     (Apply the same hostname→`.local`→ask-for-IP resolution to the **Studio** if you target it instead:
     `bogdan@MacStudio.local`.)

3. **Pull** (network + writes to the local tree → run with the sandbox disabled). Fails loudly if the remote
   project is missing:

   ```bash
   set -euo pipefail
   HOST="<the resolved host from step 2>"
   LOCAL="$(git rev-parse --show-toplevel)"
   NAME="$(basename "$LOCAL")"
   ARG="$ARGUMENTS"
   REMOTE="${ARG:-~/Development/Projects/$NAME}"
   ssh -o ConnectTimeout=8 -o BatchMode=yes "$HOST" true
   REMOTE_ABS="$(ssh "$HOST" "cd $REMOTE && pwd")"
   rsync -az --delete \
     --exclude='node_modules/' --exclude='.next/' --exclude='next-env.d.ts' \
     --exclude='.turbo/' --exclude='dist/' --exclude='build/' --exclude='out/' \
     --exclude='target/' --exclude='.idea/' --exclude='.DS_Store' --exclude='*.log' \
     "$HOST:$REMOTE_ABS/" "$LOCAL/"
   echo "Pulled $HOST:$REMOTE_ABS -> $LOCAL"
   ```

   Remote path defaults to `~/Development/Projects/<project-name>`; override via the argument.

4. **Optional bootstrap** (if the project uses bun and the pull changed dependencies): `bun install` then
   `bun verify:all` locally.

5. Report the resolved host, what was pulled, and the new local `git status` / `git log -1` so the user
   sees the incoming state.

## Notes

- If SSH fails or the remote path doesn't exist, report it — don't create an empty mirror.
- `.env` here is overwritten with the laptop's `.env` (intended — keeps credentials in sync).
- Excluded paths (`node_modules`, `.next`) on THIS machine are preserved; run the bootstrap if deps changed.
- If a project ships its own committed sync script, prefer it for project-specific excludes/bootstrap.
