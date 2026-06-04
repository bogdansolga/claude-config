#!/usr/bin/env pwsh
# Sync claude-config repo to home folders (PowerShell variant of sync-to-home.sh).
# Windows without WSL, or any pwsh 7+ host (macOS/Linux included via $HOME).
#
# Symlink creation on Windows requires elevation: enable Developer Mode
# (Settings > Privacy & security > For developers) or run this from an
# elevated (admin) PowerShell. Without it, symlink steps are reported as failed
# and skipped — config-file copies and ~/.claude-config copies still apply.
#
# Usage: ./sync-to-home.ps1 [-DryRun]

param([switch]$DryRun)

$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$ClaudeHome = Join-Path $HOME '.claude'
$ConfigHome = Join-Path $HOME '.claude-config'

function Write-Sync { param([string]$Msg) Write-Host "+ $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "- $Msg" -ForegroundColor Yellow }

if ($DryRun) {
    Write-Host 'DRY RUN - no changes will be made'
    Write-Host ''
}

Write-Host "Syncing from: $ScriptDir"
Write-Host ''

# =============================================================================
# Sync to ~/.claude
# =============================================================================
Write-Host '=== Syncing to ~/.claude ==='

if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $ClaudeHome | Out-Null }

# Config files from claude-home/
foreach ($file in @('settings.json', 'settings.local.json', 'config.json', 'hooks.json', 'CLAUDE.md', 'RTK.md')) {
    $src = Join-Path $ScriptDir "claude-home/$file"
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        if (-not $DryRun) { Copy-Item -LiteralPath $src -Destination $ClaudeHome -Force }
        Write-Sync $file
    }
}

# Symlink directories from root level — PER-ITEM, not wholesale.
#
# We do NOT replace ~/.claude/$dir with a single directory symlink because that
# would clobber sibling overrides the user has overlaid (e.g. ~/.claude/commands
# contains symlinks to other source repos like apex-claude-config and
# everything-claude-code, alongside files from personal/claude-config).
#
# Strategy per top-level item under $ScriptDir/$dir/:
#   - target absent              -> create symlink
#   - target = correct symlink   -> leave it (idempotent)
#   - target = different symlink -> preserve override, print note
#   - target = regular file/dir  -> preserve, print note (manual review needed)
Write-Host ''
Write-Host '=== Setting up symlinks (per-item) ==='

foreach ($dir in @('commands', 'scripts', 'skills', 'agents', 'output-styles', 'plugins')) {
    $srcDir = Join-Path $ScriptDir $dir
    if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { continue }

    $targetRoot = Join-Path $ClaudeHome $dir
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null }

    # -Force includes hidden/dot entries (matches the bash glob + .[!.]* pass).
    foreach ($item in Get-ChildItem -LiteralPath $srcDir -Force) {
        $name = $item.Name
        $target = Join-Path $targetRoot $name
        $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue

        if ($existing -and $existing.LinkType -eq 'SymbolicLink') {
            $current = $existing.Target
            if ($current -eq $item.FullName) {
                Write-Skip "$dir/$name (symlink already correct)"
            }
            else {
                Write-Skip "$dir/$name (override -> $current; preserved)"
            }
            continue
        }

        if ($existing) {
            Write-Skip "$dir/$name (existing non-symlink; preserved)"
            continue
        }

        if (-not $DryRun) {
            try {
                New-Item -ItemType SymbolicLink -Path $target -Value $item.FullName -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Skip "$dir/$name (symlink FAILED — enable Developer Mode or run as admin)"
                continue
            }
        }
        Write-Sync "$dir/$name -> $($item.FullName)"
    }
}

# =============================================================================
# Sync to ~/.claude-config (for backwards compatibility)
# =============================================================================
Write-Host ''
Write-Host '=== Syncing to ~/.claude-config ==='

if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $ConfigHome | Out-Null }

# Mirror key directories (remove-then-copy mirrors rsync --delete: dest exactly matches source).
foreach ($dir in @('commands', 'scripts', 'skills', 'next-docs')) {
    $srcDir = Join-Path $ScriptDir $dir
    if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { continue }

    $destDir = Join-Path $ConfigHome $dir
    if (-not $DryRun) {
        if (Test-Path -LiteralPath $destDir) { Remove-Item -LiteralPath $destDir -Recurse -Force }
        Copy-Item -LiteralPath $srcDir -Destination $destDir -Recurse -Force
    }
    Write-Sync "$dir/"
}

Write-Host ''
Write-Host '=== Summary ==='
if ($DryRun) {
    Write-Host 'Dry run complete. Run without -DryRun to apply changes.'
}
else {
    Write-Sync 'Sync complete!'
    Write-Host ''
    Write-Host 'Synced:'
    Write-Host '  ~/.claude/{settings,config,hooks}.json, CLAUDE.md, RTK.md'
    Write-Host '  ~/.claude/{commands,scripts,skills,agents,output-styles,plugins} (symlinks)'
    Write-Host '  ~/.claude-config/{commands,scripts,skills,next-docs} (copies)'
}
