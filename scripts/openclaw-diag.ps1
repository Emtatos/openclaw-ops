<#
.SYNOPSIS
    OpenClaw diagnostics — collects environment and config health info
    without ever displaying secret values.

.DESCRIPTION
    Scans the OpenClaw installation directory for configuration files,
    verifies file presence/permissions, checks service status, and
    reports connectivity.  All output is safe to share; secrets are
    never printed.

.PARAMETER OpenClawRoot
    Path to the OpenClaw installation directory.
    Defaults to the current directory.

.EXAMPLE
    .\openclaw-diag.ps1
    .\openclaw-diag.ps1 -OpenClawRoot "C:\OpenClaw"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OpenClawRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Helpers ──────────────────────────────────────────────────────────
function Write-Section([string]$Title) {
    Write-Host "`n═══ $Title ═══" -ForegroundColor Cyan
}

function Test-SecretPattern([string]$Value) {
    # Returns $true if a value looks like it might be a secret
    $patterns = @(
        '(?i)(key|secret|token|password|pwd|apikey|api_key|passphrase)',
        '^[A-Za-z0-9+/=]{20,}$',
        '^[0-9a-f]{32,}$'
    )
    foreach ($p in $patterns) {
        if ($Value -match $p) { return $true }
    }
    return $false
}

# ── 1. Environment ──────────────────────────────────────────────────
Write-Section "Environment"
Write-Host "Hostname        : $env:COMPUTERNAME"
Write-Host "OS              : $([System.Environment]::OSVersion.VersionString)"
Write-Host "PowerShell      : $($PSVersionTable.PSVersion)"
Write-Host "User            : $env:USERNAME"
Write-Host "Date (UTC)      : $((Get-Date).ToUniversalTime().ToString('o'))"
Write-Host "OpenClawRoot    : $OpenClawRoot"

# ── 2. Directory structure ──────────────────────────────────────────
Write-Section "Directory structure"

if (-not (Test-Path $OpenClawRoot)) {
    Write-Warning "OpenClawRoot '$OpenClawRoot' does not exist."
} else {
    Get-ChildItem -Path $OpenClawRoot -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        ForEach-Object {
            $rel = $_.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
            $icon = if ($_.PSIsContainer) { "[DIR] " } else { "      " }
            Write-Host "$icon$rel"
        }
}

# ── 3. Configuration files ─────────────────────────────────────────
Write-Section "Configuration files"

$configExtensions = @('*.json', '*.yaml', '*.yml', '*.toml', '*.env', '*.config', '*.ini', '*.cfg', '*.xml')
$configFiles = @()

foreach ($ext in $configExtensions) {
    $found = Get-ChildItem -Path $OpenClawRoot -Filter $ext -Recurse -ErrorAction SilentlyContinue
    $configFiles += $found
}

if ($configFiles.Count -eq 0) {
    Write-Host "No configuration files found."
} else {
    foreach ($f in $configFiles) {
        $rel = $f.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
        $size = "{0:N0} bytes" -f $f.Length
        $modified = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        Write-Host "  $rel  ($size, modified $modified)"
    }
}

# ── 4. Secret-key audit (presence only, never values) ───────────────
Write-Section "Secret-key audit"

$secretKeyPatterns = @(
    '(?i)(api[_-]?key|api[_-]?secret|password|secret|token|passphrase|private[_-]?key|credentials?)',
    '(?i)(connection[_-]?string|auth[_-]?token|access[_-]?key|client[_-]?secret)'
)

$auditResults = @()

foreach ($f in $configFiles) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    $lines = $content -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($p in $secretKeyPatterns) {
            if ($lines[$i] -match $p) {
                $rel = $f.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
                $keyName = ($lines[$i] -replace '^\s+', '') -replace ':.*$', '' -replace '=.*$', '' -replace '"', ''
                $auditResults += [PSCustomObject]@{
                    File    = $rel
                    Line    = $i + 1
                    KeyName = $keyName.Trim()
                }
                break
            }
        }
    }
}

if ($auditResults.Count -eq 0) {
    Write-Host "No secret-looking keys detected."
} else {
    Write-Host "Found $($auditResults.Count) potential secret key(s):"
    $auditResults | Format-Table -AutoSize
    Write-Host "(Values are NOT shown — use openclaw-redact.ps1 before sharing config.)" -ForegroundColor Yellow
}

# ── 5. .NET / runtime check ─────────────────────────────────────────
Write-Section ".NET / Runtime"

try {
    $dotnet = & dotnet --info 2>&1
    $version = ($dotnet | Select-String 'Version:' | Select-Object -First 1).ToString().Trim()
    Write-Host "dotnet: $version"
} catch {
    Write-Host "dotnet: not found"
}

try {
    $node = & node --version 2>&1
    Write-Host "node  : $node"
} catch {
    Write-Host "node  : not found"
}

try {
    $python = & python --version 2>&1
    Write-Host "python: $python"
} catch {
    Write-Host "python: not found"
}

# ── 6. Network connectivity ─────────────────────────────────────────
Write-Section "Network connectivity"

$endpoints = @(
    @{ Name = "Kraken REST API";      Uri = "https://api.kraken.com/0/public/SystemStatus" },
    @{ Name = "Kraken WebSocket";     Uri = "https://ws.kraken.com" },
    @{ Name = "GitHub (updates)";     Uri = "https://api.github.com" }
)

foreach ($ep in $endpoints) {
    try {
        $resp = Invoke-WebRequest -Uri $ep.Uri -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        Write-Host "  [OK]   $($ep.Name) ($($ep.Uri)) — HTTP $($resp.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($ep.Name) ($($ep.Uri)) — $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ── 7. Process / service check ──────────────────────────────────────
Write-Section "Process / service check"

$processNames = @('OpenClaw', 'openclaw', 'dotnet')

foreach ($name in $processNames) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
        foreach ($p in $procs) {
            Write-Host "  [RUNNING] $($p.ProcessName) (PID $($p.Id), CPU $([math]::Round($p.CPU, 2))s)" -ForegroundColor Green
        }
    } else {
        Write-Host "  [NOT RUNNING] $name" -ForegroundColor DarkGray
    }
}

# ── 8. Log tail ──────────────────────────────────────────────────────
Write-Section "Recent log entries (last 20 lines)"

$logPatterns = @('*.log', 'logs/*.log', 'log/*.log', '*.log.txt')
$logFiles = @()

foreach ($lp in $logPatterns) {
    $logFiles += Get-ChildItem -Path $OpenClawRoot -Filter $lp -Recurse -ErrorAction SilentlyContinue
}

if ($logFiles.Count -eq 0) {
    Write-Host "No log files found."
} else {
    $newest = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $rel = $newest.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
    Write-Host "Log file: $rel (modified $($newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))"
    Write-Host "─────────────────────────────────────────────"
    Get-Content $newest.FullName -Tail 20 -ErrorAction SilentlyContinue |
        ForEach-Object {
            # Redact anything that looks like a secret in log output
            $line = $_ -replace '(?i)(key|secret|token|password|passphrase)\s*[=:]\s*\S+', '$1=***REDACTED***'
            Write-Host "  $line"
        }
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Section "Summary"
Write-Host "Diagnostics complete. No secrets were displayed."
Write-Host "Config files found : $($configFiles.Count)"
Write-Host "Secret keys found  : $($auditResults.Count)"
Write-Host "Log files found    : $($logFiles.Count)"
Write-Host ""
Write-Host "Next step: run .\openclaw-redact.ps1 to create a safe, shareable copy." -ForegroundColor Yellow
