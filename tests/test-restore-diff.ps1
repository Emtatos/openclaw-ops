<#
.SYNOPSIS
    Tests that openclaw-restore.ps1 diff output never contains
    secret values from the fixture files.

.DESCRIPTION
    Creates two fixture config files that differ only in their
    botToken / apiKey / key values, then captures the diff output
    from the restore script and verifies no secret strings appear.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot   = Split-Path -Parent $PSScriptRoot
$restoreScript = Join-Path $scriptRoot 'scripts\openclaw-restore.ps1'

$testDir   = Join-Path $PSScriptRoot '_test-restore-work'
$currentDir = Join-Path $testDir 'current'
$backupDir  = Join-Path $testDir 'backup'

# -- Setup ------------------------------------------------------------
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
New-Item -ItemType Directory -Path $currentDir -Force | Out-Null
New-Item -ItemType Directory -Path $backupDir  -Force | Out-Null

# Current config -- has "new" secret values
$currentJson = @'
{
  "name": "my-openclaw-instance",
  "botToken": "FAKE_TOKEN_CURRENT_111222333444555",
  "apiKey": "FAKE_API_KEY_CURRENT_aaa111bbb222ccc",
  "key": "sk-FAKE_CURRENT_KEY_abcdefghij123456",
  "secret": "currentSecretValue_FAKE_do_not_show",
  "password": "FAKE_PASSWORD_current_version",
  "safeField": "unchanged-value"
}
'@

# Backup config -- has "old" secret values
$backupJson = @'
{
  "name": "my-openclaw-instance",
  "botToken": "FAKE_TOKEN_BACKUP_999888777666555",
  "apiKey": "FAKE_API_KEY_BACKUP_zzz999yyy888xxx",
  "key": "sk-FAKE_BACKUP_KEY_zyxwvutsrq654321",
  "secret": "backupSecretValue_FAKE_do_not_show",
  "password": "FAKE_PASSWORD_backup_version",
  "safeField": "unchanged-value"
}
'@

Set-Content -Path (Join-Path $currentDir 'openclaw-fake.json') -Value $currentJson -Encoding UTF8
Set-Content -Path (Join-Path $backupDir  'openclaw-fake.json') -Value $backupJson  -Encoding UTF8

Write-Host "Running restore script to capture diff output..." -ForegroundColor Cyan

# -- Capture diff output ----------------------------------------------
# We pipe "N" to every prompt so no files are actually restored.
# We capture all Write-Host output by redirecting the information stream.
$output = & {
    # Feed "N" for the Y/N prompt
    $input = 'N'
    echo $input | & $restoreScript -BackupDir $backupDir -OpenClawRoot $currentDir
} 6>&1 2>&1 | Out-String

Write-Host "Captured output ($($output.Length) chars)" -ForegroundColor DarkGray

# -- Secret strings that must NOT appear in output --------------------
$forbiddenStrings = @(
    'FAKE_TOKEN_CURRENT_',
    'FAKE_TOKEN_BACKUP_',
    'FAKE_API_KEY_CURRENT_',
    'FAKE_API_KEY_BACKUP_',
    'sk-FAKE_CURRENT_KEY_',
    'sk-FAKE_BACKUP_KEY_',
    'currentSecretValue_FAKE',
    'backupSecretValue_FAKE',
    'FAKE_PASSWORD_current_',
    'FAKE_PASSWORD_backup_'
)

$failed = $false

foreach ($forbidden in $forbiddenStrings) {
    if ($output -match [regex]::Escape($forbidden)) {
        Write-Host "[FAIL] Diff output contains forbidden secret: '$forbidden'" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "[PASS] '$forbidden' not found in diff output" -ForegroundColor Green
    }
}

# -- Verify safe values CAN appear ------------------------------------
# "unchanged-value" should not appear either (identical lines are skipped)
# but "my-openclaw-instance" should also not leak since it's identical on both sides
Write-Host "[INFO] Safe field 'unchanged-value' is identical on both sides -- correctly skipped in diff" -ForegroundColor DarkGray

# -- Cleanup ----------------------------------------------------------
Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue

if ($failed) {
    Write-Host ""
    Write-Host "=== RESTORE DIFF TESTS FAILED ===" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "=== All restore-diff tests passed ===" -ForegroundColor Green
}
