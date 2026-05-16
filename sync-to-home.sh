#!/bin/bash

# Sync claude-config repo to home folders
# Usage: ./sync-to-home.sh [--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=""

if [ "$1" == "--dry-run" ]; then
    DRY_RUN="--dry-run"
    echo "DRY RUN - no changes will be made"
    echo ""
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_sync() { echo -e "${GREEN}✓${NC} $1"; }
print_skip() { echo -e "${YELLOW}→${NC} $1"; }

echo "Syncing from: $SCRIPT_DIR"
echo ""

# =============================================================================
# Sync to ~/.claude
# =============================================================================
echo "=== Syncing to ~/.claude ==="

# Config files from claude-home/
for file in settings.json settings.local.json config.json hooks.json CLAUDE.md RTK.md; do
    if [ -f "$SCRIPT_DIR/claude-home/$file" ]; then
        rsync -av $DRY_RUN "$SCRIPT_DIR/claude-home/$file" ~/.claude/
        print_sync "$file"
    fi
done

# Symlink directories from root level
echo ""
echo "=== Setting up symlinks ==="

for dir in commands scripts skills agents output-styles plugins; do
    if [ -d "$SCRIPT_DIR/$dir" ]; then
        # Remove existing (file, symlink, or directory)
        if [ -e ~/.claude/$dir ] || [ -L ~/.claude/$dir ]; then
            rm -rf ~/.claude/$dir 2>/dev/null || true
        fi
        if [ -z "$DRY_RUN" ]; then
            ln -s "$SCRIPT_DIR/$dir" ~/.claude/$dir
        fi
        print_sync "~/.claude/$dir -> $SCRIPT_DIR/$dir"
    fi
done

# =============================================================================
# Sync to ~/.claude-config (for backwards compatibility)
# =============================================================================
echo ""
echo "=== Syncing to ~/.claude-config ==="

mkdir -p ~/.claude-config

# Sync key directories
for dir in commands scripts skills next-docs; do
    if [ -d "$SCRIPT_DIR/$dir" ]; then
        rsync -av $DRY_RUN --delete "$SCRIPT_DIR/$dir/" ~/.claude-config/$dir/
        print_sync "$dir/"
    fi
done

echo ""
echo "=== Summary ==="
if [ -n "$DRY_RUN" ]; then
    echo "Dry run complete. Run without --dry-run to apply changes."
else
    print_sync "Sync complete!"
    echo ""
    echo "Synced:"
    echo "  ~/.claude/{settings,config,hooks}.json, CLAUDE.md, RTK.md"
    echo "  ~/.claude/{commands,scripts,skills,agents,output-styles,plugins} (symlinks)"
    echo "  ~/.claude-config/{commands,scripts,skills,next-docs} (copies)"
fi
