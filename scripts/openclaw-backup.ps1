<#
.SYNOPSIS
    Creates a timestamped backup of OpenClaw configuration files.

.DESCRIPTION
    Copies all configuration files from the OpenClaw installation
    directory into a timestamped subfolder under the backup root.
    Original files are never modified.  Each backup is self-contained
    and can later be restored with openclaw-restore.ps1.

.PARAMETER OpenClawRoot
    Path to the OpenClaw installation directory.
    Defaults to the current directory.

.PARAMETER BackupRoot
    Parent folder for backup snapshots.
    Defaults to ./openclaw-backups (relative to working directory).

.PARAMETER Tag
    Optional label appended to the backup folder name
    (e.g. "before-upgrade").

.EXAMPLE
    .\openclaw-backup.ps1
    .\openclaw-backup.ps1 -OpenClawRoot "C:\OpenClaw" -Tag "pre-v2"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OpenClawRoot = (Get-Location).Path,

    [Parameter()]
    [string]$BackupRoot = (Join-Path (Get-Location).Path 'openclaw-backups'),

    [Parameter()]
    [string]$Tag = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Build backup folder name ─────────────────────────────────────────
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$folderName = if ($Tag) { "${timestamp}_${Tag}" } else { $timestamp }
$backupDir  = Join-Path $BackupRoot $folderName

# ── Discover config files ────────────────────────────────────────────
$configExtensions = @('*.json', '*.yaml', '*.yml', '*.toml', '*.env', '*.config', '*.ini', '*.cfg', '*.xml')
$configFiles = @()

foreach ($ext in $configExtensions) {
    $configFiles += Get-ChildItem -Path $OpenClawRoot -Filter $ext -Recurse -ErrorAction SilentlyContinue
}

if ($configFiles.Count -eq 0) {
    Write-Host "No configuration files found in '$OpenClawRoot'. Nothing to back up." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($configFiles.Count) configuration file(s) to back up." -ForegroundColor Cyan

# ── Create backup directory ──────────────────────────────────────────
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

# ── Copy files ───────────────────────────────────────────────────────
$copied = 0

foreach ($f in $configFiles) {
    $relativePath = $f.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
    $destPath     = Join-Path $backupDir $relativePath
    $destDir      = Split-Path $destPath -Parent

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -Path $f.FullName -Destination $destPath -Force
    Write-Host "  [BACKED UP] $relativePath" -ForegroundColor Green
    $copied++
}

# ── Write manifest ───────────────────────────────────────────────────
$manifest = @{
    Timestamp    = (Get-Date).ToUniversalTime().ToString('o')
    OpenClawRoot = $OpenClawRoot
    Tag          = $Tag
    FileCount    = $copied
    Files        = $configFiles | ForEach-Object {
        $_.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
    }
}

$manifestPath = Join-Path $backupDir '_backup-manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══ Backup complete ═══" -ForegroundColor Cyan
Write-Host "Files backed up : $copied"
Write-Host "Backup location : $backupDir"
Write-Host "Manifest        : $manifestPath"
Write-Host ""
Write-Host "To restore, run:" -ForegroundColor Yellow
Write-Host "  .\openclaw-restore.ps1 -BackupDir '$backupDir'" -ForegroundColor Yellow
