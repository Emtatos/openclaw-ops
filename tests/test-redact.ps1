<#
.SYNOPSIS
    Tests that openclaw-redact.ps1 produces valid JSON and correctly
    redacts secret fields while leaving safe fields intact.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSScriptRoot
$redactScript = Join-Path $scriptRoot 'scripts' 'openclaw-redact.ps1'
$fixtureDir   = Join-Path $PSScriptRoot 'fixtures'
$outputDir    = Join-Path $PSScriptRoot '_test-redacted-output'

# Clean previous run
if (Test-Path $outputDir) { Remove-Item $outputDir -Recurse -Force }

# ── Run redaction ────────────────────────────────────────────────────
Write-Host "Running openclaw-redact.ps1 on fixtures..." -ForegroundColor Cyan
& $redactScript -OpenClawRoot $fixtureDir -OutputDir $outputDir

# ── Test 1: Output file exists ───────────────────────────────────────
$redactedFile = Join-Path $outputDir 'openclaw-fake.json'
if (-not (Test-Path $redactedFile)) {
    Write-Host "[FAIL] Redacted file not found at $redactedFile" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] Redacted file exists" -ForegroundColor Green

# ── Test 2: Output is valid JSON ─────────────────────────────────────
$content = Get-Content $redactedFile -Raw
try {
    $parsed = $content | ConvertFrom-Json
    Write-Host "[PASS] Redacted output is valid JSON" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Redacted output is NOT valid JSON: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Content:" -ForegroundColor Yellow
    Write-Host $content
    exit 1
}

# ── Test 3: botToken is redacted ─────────────────────────────────────
if ($content -match 'FAKE_TOKEN_') {
    Write-Host "[FAIL] botToken value 'FAKE_TOKEN_*' was NOT redacted" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] botToken is redacted" -ForegroundColor Green

# ── Test 4: apiKey is redacted ───────────────────────────────────────
if ($content -match 'FAKE_API_KEY_') {
    Write-Host "[FAIL] apiKey value 'FAKE_API_KEY_*' was NOT redacted" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] apiKey is redacted" -ForegroundColor Green

# ── Test 5: key is redacted ─────────────────────────────────────────
if ($content -match 'sk-FAKE_SECRET_KEY') {
    Write-Host "[FAIL] key value 'sk-*' was NOT redacted" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] key is redacted" -ForegroundColor Green

# ── Test 6: secret is redacted ───────────────────────────────────────
if ($content -match 'superSecretValue') {
    Write-Host "[FAIL] secret value was NOT redacted" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] secret is redacted" -ForegroundColor Green

# ── Test 7: password is redacted ─────────────────────────────────────
if ($content -match 'FAKE_PASSWORD_') {
    Write-Host "[FAIL] password value was NOT redacted" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] password is redacted" -ForegroundColor Green

# ── Test 8: Safe fields are intact ───────────────────────────────────
if ($parsed.safeField -ne 'this-value-should-not-be-redacted') {
    Write-Host "[FAIL] safeField was incorrectly modified: $($parsed.safeField)" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] safeField is intact" -ForegroundColor Green

if ($parsed.anotherSafe -ne 42) {
    Write-Host "[FAIL] anotherSafe was incorrectly modified: $($parsed.anotherSafe)" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] anotherSafe is intact" -ForegroundColor Green

if ($parsed.name -ne 'my-openclaw-instance') {
    Write-Host "[FAIL] name was incorrectly modified: $($parsed.name)" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] name is intact" -ForegroundColor Green

if ($parsed.description -ne 'Test instance for CI verification') {
    Write-Host "[FAIL] description was incorrectly modified" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] description is intact" -ForegroundColor Green

# ── Test 9: _redaction-manifest.json exists ──────────────────────────
$manifestFile = Join-Path $outputDir '_redaction-manifest.json'
if (-not (Test-Path $manifestFile)) {
    Write-Host "[FAIL] _redaction-manifest.json not found" -ForegroundColor Red
    exit 1
}

try {
    $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
    Write-Host "[PASS] _redaction-manifest.json exists and is valid JSON" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] _redaction-manifest.json is not valid JSON" -ForegroundColor Red
    exit 1
}

# ── Cleanup ──────────────────────────────────────────────────────────
Remove-Item $outputDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "═══ All redaction tests passed ═══" -ForegroundColor Green
