<#
.SYNOPSIS
    Restores OpenClaw configuration files from a backup — with
    per-file diff review and explicit Y/N confirmation.

.DESCRIPTION
    Reads files from a backup folder (created by openclaw-backup.ps1),
    compares each file to its current counterpart, displays a diff,
    and prompts the operator for Y/N confirmation before overwriting.

    NOTHING is written automatically.  Every file requires explicit
    approval.

.PARAMETER BackupDir
    Path to the backup snapshot folder (the timestamped folder inside
    openclaw-backups/).

.PARAMETER OpenClawRoot
    Path to the OpenClaw installation directory where files will be
    restored to.  Defaults to the current directory.

.EXAMPLE
    .\openclaw-restore.ps1 -BackupDir ".\openclaw-backups\2025-05-01_143000"
    .\openclaw-restore.ps1 -BackupDir ".\openclaw-backups\2025-05-01_143000_pre-v2" -OpenClawRoot "C:\OpenClaw"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,

    [Parameter()]
    [string]$OpenClawRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Validate backup directory ────────────────────────────────────────
if (-not (Test-Path $BackupDir)) {
    Write-Error "Backup directory '$BackupDir' does not exist."
    exit 1
}

$manifestPath = Join-Path $BackupDir '_backup-manifest.json'
$hasManifest  = Test-Path $manifestPath

if ($hasManifest) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    Write-Host "═══ Backup manifest ═══" -ForegroundColor Cyan
    Write-Host "  Created : $($manifest.Timestamp)"
    Write-Host "  Source  : $($manifest.OpenClawRoot)"
    Write-Host "  Tag     : $(if ($manifest.Tag) { $manifest.Tag } else { '(none)' })"
    Write-Host "  Files   : $($manifest.FileCount)"
    Write-Host ""
}

# ── Discover files to restore ────────────────────────────────────────
$backupFiles = Get-ChildItem -Path $BackupDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '_backup-manifest.json' }

if ($backupFiles.Count -eq 0) {
    Write-Host "No files found in backup directory." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($backupFiles.Count) file(s) in backup." -ForegroundColor Cyan
Write-Host "Each file will be shown with a diff. You must approve (Y) or skip (N) each one." -ForegroundColor Yellow
Write-Host ""

# ── Helper: simple line-by-line diff ─────────────────────────────────
function Show-Diff {
    param(
        [string]$CurrentContent,
        [string]$BackupContent
    )

    $currentLines = if ($CurrentContent) { $CurrentContent -split "`n" } else { @() }
    $backupLines  = $BackupContent -split "`n"

    $maxLines = [Math]::Max($currentLines.Count, $backupLines.Count)

    $hasDiff = $false

    for ($i = 0; $i -lt $maxLines; $i++) {
        $cur = if ($i -lt $currentLines.Count) { $currentLines[$i].TrimEnd("`r") } else { $null }
        $bak = if ($i -lt $backupLines.Count)  { $backupLines[$i].TrimEnd("`r")  } else { $null }

        if ($cur -eq $bak) {
            continue
        }

        $hasDiff = $true
        $lineNum = $i + 1

        if ($null -eq $cur) {
            Write-Host "  Line ${lineNum}:" -ForegroundColor DarkGray
            Write-Host "    + (backup)  : $bak" -ForegroundColor Green
        } elseif ($null -eq $bak) {
            Write-Host "  Line ${lineNum}:" -ForegroundColor DarkGray
            Write-Host "    - (current) : $cur" -ForegroundColor Red
        } else {
            Write-Host "  Line ${lineNum}:" -ForegroundColor DarkGray
            Write-Host "    - (current) : $cur" -ForegroundColor Red
            Write-Host "    + (backup)  : $bak" -ForegroundColor Green
        }
    }

    return $hasDiff
}

# ── Process each file ────────────────────────────────────────────────
$restored = 0
$skipped  = 0

foreach ($bf in $backupFiles) {
    $relativePath = $bf.FullName.Substring($BackupDir.Length).TrimStart('\', '/')
    $currentPath  = Join-Path $OpenClawRoot $relativePath

    Write-Host "───────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "File: $relativePath" -ForegroundColor White

    $backupContent = Get-Content $bf.FullName -Raw -ErrorAction SilentlyContinue

    if (Test-Path $currentPath) {
        $currentContent = Get-Content $currentPath -Raw -ErrorAction SilentlyContinue

        if ($currentContent -eq $backupContent) {
            Write-Host "  [IDENTICAL] Current file matches backup. Skipping." -ForegroundColor DarkGray
            $skipped++
            continue
        }

        Write-Host "  Differences:" -ForegroundColor Yellow
        $hasDiff = Show-Diff -CurrentContent $currentContent -BackupContent $backupContent

        if (-not $hasDiff) {
            Write-Host "  [IDENTICAL] Only whitespace differences. Skipping." -ForegroundColor DarkGray
            $skipped++
            continue
        }
    } else {
        Write-Host "  [NEW] File does not exist at destination. Full content from backup:" -ForegroundColor Yellow
        $preview = ($backupContent -split "`n" | Select-Object -First 15) -join "`n"
        Write-Host $preview -ForegroundColor DarkGray
        if (($backupContent -split "`n").Count -gt 15) {
            Write-Host "  ... ($(($backupContent -split "`n").Count - 15) more lines)" -ForegroundColor DarkGray
        }
    }

    # ── Prompt for confirmation ──────────────────────────────────────
    Write-Host ""
    do {
        $answer = Read-Host "  Restore '$relativePath'? (Y/N)"
        $answer = $answer.Trim().ToUpper()
    } while ($answer -notin @('Y', 'N'))

    if ($answer -eq 'Y') {
        $destDir = Split-Path $currentPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Set-Content -Path $currentPath -Value $backupContent -Encoding UTF8 -NoNewline
        Write-Host "  [RESTORED] $relativePath" -ForegroundColor Green
        $restored++
    } else {
        Write-Host "  [SKIPPED]  $relativePath" -ForegroundColor DarkGray
        $skipped++
    }
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══ Restore complete ═══" -ForegroundColor Cyan
Write-Host "Files restored : $restored"
Write-Host "Files skipped  : $skipped"
Write-Host "Total in backup: $($backupFiles.Count)"

if ($restored -gt 0) {
    Write-Host ""
    Write-Host "Tip: run .\openclaw-diag.ps1 to verify the restored configuration." -ForegroundColor Yellow
}
