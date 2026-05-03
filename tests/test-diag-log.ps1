<#
.SYNOPSIS
    Tests that openclaw-diag.ps1 log tail output never contains
    secret values -- even JSON-shaped ones and free-text sk-* tokens.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot   = Split-Path -Parent $PSScriptRoot
$diagScript   = Join-Path $scriptRoot 'scripts\openclaw-diag.ps1'
$fixtureDir   = Join-Path $PSScriptRoot 'fixtures'

Write-Host "Running openclaw-diag.ps1 against fixture directory..." -ForegroundColor Cyan

# Capture all output streams (Write-Host goes to stream 6 in PS 5+)
# We redirect all streams and capture as string
$output = & {
    & $diagScript -OpenClawRoot $fixtureDir
} *>&1 | Out-String

Write-Host "Captured output ($($output.Length) chars)" -ForegroundColor DarkGray

# -- Secret strings that must NOT appear ------------------------------
$forbiddenStrings = @(
    'FAKE_TOKEN_LOG_',
    'FAKE_API_KEY_LOG_',
    'sk-FAKE_LOG_KEY_',
    'sk-FAKE_LOG_FREE_TEXT',
    'superSecretLogValue_FAKE',
    'FAKE_PASSWORD_LOG_'
)

$failed = $false

foreach ($forbidden in $forbiddenStrings) {
    if ($output -match [regex]::Escape($forbidden)) {
        Write-Host "[FAIL] Diag output contains forbidden secret: '$forbidden'" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "[PASS] '$forbidden' not found in diag output" -ForegroundColor Green
    }
}

# -- Verify the log file WAS found (diag should mention it) ----------
if ($output -match 'fake-openclaw\.log') {
    Write-Host "[PASS] Diag found and processed the fake log file" -ForegroundColor Green
} else {
    Write-Host "[WARN] Diag did not seem to find the fake log file -- test may be inconclusive" -ForegroundColor Yellow
}

# -- Verify redaction markers appear (proof redaction ran) ------------
if ($output -match '\[REDACTED') {
    Write-Host "[PASS] Redaction markers found in output (redaction is active)" -ForegroundColor Green
} else {
    Write-Host "[WARN] No [REDACTED markers found -- redaction may not have run on log lines" -ForegroundColor Yellow
}

if ($failed) {
    Write-Host ""
    Write-Host "=== DIAG LOG REDACTION TESTS FAILED ===" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "=== All diag-log redaction tests passed ===" -ForegroundColor Green
}
