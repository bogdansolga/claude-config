---
command: sync:to-laptop
description: Mirror the current project to the laptop dev box (code + .git + .env), resolving the laptop by hostname (no hardcoded IP)
---

# Sync project → laptop

Mirror the **current git project** from this machine **to the laptop** so work can continue there.

## Peer registry (resolve by hostname, never a hardcoded IP)

| Machine | mDNS hostname | ssh user |
|---------|---------------|----------|
| Laptop  | `NB01GAVL003` | `bsolga` |
| Studio  | `MacStudio`   | `bogdan` |

The remote peer for this command is the **laptop**. IPs change, so resolve it on the network instead of
hardcoding one. Override the whole target with the `LAPTOP_HOST` env var (`user@host`) to skip resolution.

## Steps

1. **Resolve the laptop's address.** Try mDNS (`<hostname>.local`); only ask for an IP if that fails:

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
     (Do the same hostname→`.local`→ask-for-IP resolution if you ever target the **Studio** instead:
     `bogdan@MacStudio.local`.)

2. **Mirror** (network + remote-write → run with the sandbox disabled). Includes `.git` + the gitignored
   `.env`; excludes regenerable artifacts. `--delete` makes the laptop an exact mirror, but excluded paths
   (its `node_modules`/`.next`) are preserved (no `--delete-excluded`):

   ```bash
   set -euo pipefail
   HOST="<the resolved host from step 1>"
   LOCAL="$(git rev-parse --show-toplevel)"
   NAME="$(basename "$LOCAL")"
   ARG="$ARGUMENTS"
   REMOTE="${ARG:-~/Development/Projects/$NAME}"
   ssh -o ConnectTimeout=8 -o BatchMode=yes "$HOST" true
   REMOTE_ABS="$(ssh "$HOST" "mkdir -p $REMOTE && cd $REMOTE && pwd")"
   rsync -az --delete \
     --exclude='node_modules/' --exclude='.next/' --exclude='next-env.d.ts' \
     --exclude='.turbo/' --exclude='dist/' --exclude='build/' --exclude='out/' \
     --exclude='target/' --exclude='.idea/' --exclude='.DS_Store' --exclude='*.log' \
     "$LOCAL/" "$HOST:$REMOTE_ABS/"
   echo "Synced $LOCAL -> $HOST:$REMOTE_ABS"
   ```

   Remote path defaults to `~/Development/Projects/<project-name>`; override by passing an explicit path as
   the argument, e.g. `/sync:to-laptop ~/code/foo`.

3. **Optional bootstrap** (only if the project uses bun and you want the laptop ready-to-run):

   ```bash
   ssh "$HOST" "bash -lc 'export PATH=\$HOME/.bun/bin:\$PATH; cd $REMOTE_ABS && bun install && bun verify:all'"
   ```

4. Report the resolved host, the remote path, and whether the bootstrap ran/passed.

## Notes

- ⚠️ This **overwrites the laptop's working tree** for the project. If the laptop may hold uncommitted work,
  reconcile first (`/sync:from-laptop`) before running this.
- `.env` on the laptop is overwritten with this machine's `.env` (intended — keeps credentials in sync).
- If a project ships its own committed sync script (e.g. `scripts/sync/sync-to-host.sh`), prefer it.
