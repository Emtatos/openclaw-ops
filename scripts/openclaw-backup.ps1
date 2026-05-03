<#
.SYNOPSIS
    Creates a timestamped backup of known OpenClaw configuration files.

.DESCRIPTION
    Copies a known allowlist of OpenClaw config files into a timestamped
    subfolder under the backup root.  Original files are never modified.
    Each backup is self-contained and can later be restored with
    openclaw-restore.ps1.

    By default only core config files are backed up.  Use -IncludeSessions
    to also include session data.

.PARAMETER OpenClawRoot
    Path to the OpenClaw installation directory.
    Defaults to $env:USERPROFILE\.openclaw.

.PARAMETER BackupRoot
    Parent folder for backup snapshots.
    Defaults to openclaw-backups under OpenClawRoot.

.PARAMETER Tag
    Optional label appended to the backup folder name
    (e.g. "before-upgrade").

.PARAMETER IncludeSessions
    When set, also backs up session files.

.EXAMPLE
    .\openclaw-backup.ps1
    .\openclaw-backup.ps1 -Tag "pre-v2"
    .\openclaw-backup.ps1 -IncludeSessions -Tag "full-snapshot"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OpenClawRoot = (Join-Path $env:USERPROFILE '.openclaw'),

    [Parameter()]
    [string]$BackupRoot = '',

    [Parameter()]
    [string]$Tag = '',

    [Parameter()]
    [switch]$IncludeSessions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $BackupRoot) {
    $BackupRoot = Join-Path $OpenClawRoot 'openclaw-backups'
}

# -- Known config file allowlist --------------------------------------
$coreFiles = @(
    'openclaw.json',
    'exec-approvals.json',
    'node.json',
    'nodes\paired.json',
    'nodes\pending.json',
    'agents\main\agent\auth-profiles.json'
)

$sessionGlob = 'sessions'

# -- Build backup folder name -----------------------------------------
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$folderName = if ($Tag) { "${timestamp}_${Tag}" } else { $timestamp }
$backupDir  = Join-Path $BackupRoot $folderName

# -- Collect files to back up -----------------------------------------
$filesToBackup = @()

foreach ($rel in $coreFiles) {
    $full = Join-Path $OpenClawRoot $rel
    if (Test-Path $full) {
        $filesToBackup += [PSCustomObject]@{
            RelativePath = $rel
            FullPath     = $full
        }
    }
}

if ($IncludeSessions) {
    $sessDir = Join-Path $OpenClawRoot $sessionGlob
    if (Test-Path $sessDir) {
        Get-ChildItem -Path $sessDir -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $rel = $_.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
                $filesToBackup += [PSCustomObject]@{
                    RelativePath = $rel
                    FullPath     = $_.FullName
                }
            }
    }
}

if (@($filesToBackup).Count -eq 0) {
    Write-Host "No known OpenClaw configuration files found in '$OpenClawRoot'. Nothing to back up." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $(@($filesToBackup).Count) file(s) to back up." -ForegroundColor Cyan

# -- Create backup directory ------------------------------------------
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

# -- Copy files -------------------------------------------------------
$copied = 0

foreach ($f in $filesToBackup) {
    $destPath = Join-Path $backupDir $f.RelativePath
    $destDir  = Split-Path $destPath -Parent

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -Path $f.FullPath -Destination $destPath -Force
    Write-Host "  [BACKED UP] $($f.RelativePath)" -ForegroundColor Green
    $copied++
}

# -- Write manifest ---------------------------------------------------
$manifest = @{
    Timestamp       = (Get-Date).ToUniversalTime().ToString('o')
    OpenClawRoot    = $OpenClawRoot
    Tag             = $Tag
    IncludeSessions = [bool]$IncludeSessions
    FileCount       = $copied
    Files           = $filesToBackup | ForEach-Object { $_.RelativePath }
}

$manifestPath = Join-Path $backupDir '_backup-manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

# -- Summary ----------------------------------------------------------
Write-Host ""
Write-Host "=== Backup complete ===" -ForegroundColor Cyan
Write-Host "Files backed up : $copied"
Write-Host "Backup location : $backupDir"
Write-Host "Manifest        : $manifestPath"
Write-Host ""
Write-Host "To restore, run:" -ForegroundColor Yellow
Write-Host "  .\openclaw-restore.ps1 -BackupDir '$backupDir'" -ForegroundColor Yellow
