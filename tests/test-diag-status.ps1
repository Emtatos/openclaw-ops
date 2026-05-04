<#
.SYNOPSIS
    Tests that openclaw-diag.ps1 correctly:
    - Does NOT mark CLI errors as [OK]
    - Excludes node_modules from config scan
    - Still redacts secrets in config/log output
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot   = Split-Path -Parent $PSScriptRoot
$diagScript   = Join-Path $scriptRoot 'scripts\openclaw-diag.ps1'
$fixtureDir   = Join-Path $PSScriptRoot 'fixtures'

# -- Setup: create node_modules with a fake package.json --------------
$nodeModulesDir = Join-Path $fixtureDir 'node_modules'
$fakePackageDir = Join-Path $nodeModulesDir 'fake-pkg'
if (-not (Test-Path $fakePackageDir)) {
    New-Item -ItemType Directory -Path $fakePackageDir -Force | Out-Null
}
$fakePackageJson = Join-Path $fakePackageDir 'package.json'
Set-Content -Path $fakePackageJson -Value '{"name":"fake-pkg","version":"1.0.0","password":"FAKE_NODE_MODULE_SECRET"}' -Encoding UTF8

$failed = $false

# -- Run diag and capture output --------------------------------------
Write-Host "Running openclaw-diag.ps1 against fixture directory..." -ForegroundColor Cyan

$output = & {
    & $diagScript -OpenClawRoot $fixtureDir
} *>&1 | Out-String

Write-Host "Captured output ($($output.Length) chars)" -ForegroundColor DarkGray

# -- Test 1: node_modules should be excluded from config scan ---------
if ($output -match 'node_modules') {
    Write-Host "[FAIL] Diag output mentions node_modules (should be excluded)" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "[PASS] node_modules excluded from config scan" -ForegroundColor Green
}

# -- Test 2: FAKE_NODE_MODULE_SECRET should not appear ----------------
if ($output -match 'FAKE_NODE_MODULE_SECRET') {
    Write-Host "[FAIL] Secret from node_modules leaked into output" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "[PASS] Secrets from node_modules not leaked" -ForegroundColor Green
}

# -- Test 3: CLI error output should NOT be marked [OK] ---------------
# The diag script checks for 'error:' in CLI output.
# Since openclaw CLI is not installed, it shows 'not found' which is fine.
# Verify that any [OK] lines don't contain 'error:'
$okLines = @($output -split "`n" | Where-Object { $_ -match '\[OK\]' })
$badOk = $false
foreach ($line in $okLines) {
    if ($line -match '(?i)error:') {
        Write-Host "[FAIL] Line marked [OK] contains 'error:': $line" -ForegroundColor Red
        $failed = $true
        $badOk = $true
    }
}
if (-not $badOk) {
    Write-Host "[PASS] No [OK] lines contain error indicators" -ForegroundColor Green
}

# -- Test 4: Process check should use [INFO] not [NOT RUNNING] -------
if ($output -match '\[NOT RUNNING\]') {
    Write-Host "[FAIL] Output still uses misleading [NOT RUNNING] label" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "[PASS] Process check uses [INFO] instead of [NOT RUNNING]" -ForegroundColor Green
}

# -- Test 5: Secrets from fixtures still redacted ---------------------
$forbiddenStrings = @(
    'FAKE_TOKEN_LOG_',
    'FAKE_API_KEY_LOG_',
    'sk-FAKE_LOG_KEY_',
    'sk-FAKE_LOG_FREE_TEXT',
    'FAKE_PASSWORD_LOG_'
)
foreach ($forbidden in $forbiddenStrings) {
    if ($output -match [regex]::Escape($forbidden)) {
        Write-Host "[FAIL] Diag output contains forbidden secret: '$forbidden'" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "[PASS] '$forbidden' not found in diag output" -ForegroundColor Green
    }
}

# -- Cleanup: remove test node_modules --------------------------------
Remove-Item $nodeModulesDir -Recurse -Force -ErrorAction SilentlyContinue

if ($failed) {
    Write-Host ""
    Write-Host "=== DIAG STATUS TESTS FAILED ===" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "=== All diag-status tests passed ===" -ForegroundColor Green
}
