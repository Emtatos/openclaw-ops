<#
.SYNOPSIS
    Redacts secrets from OpenClaw configuration files and writes
    sanitised copies to ./openclaw-redacted/.

.DESCRIPTION
    Scans configuration files for values that look like API keys,
    passwords, tokens, connection strings, etc. and replaces them
    with safe placeholder text.  Original files are NEVER modified.

    The output folder (./openclaw-redacted/) can be opened in
    Notepad, reviewed, and then safely pasted into AI assistants
    or support tickets.

.PARAMETER OpenClawRoot
    Path to the OpenClaw installation directory.
    Defaults to the current directory.

.PARAMETER OutputDir
    Path where redacted copies are written.
    Defaults to ./openclaw-redacted (relative to working directory).

.EXAMPLE
    .\openclaw-redact.ps1
    .\openclaw-redact.ps1 -OpenClawRoot "C:\OpenClaw" -OutputDir "C:\safe-share"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OpenClawRoot = (Get-Location).Path,

    [Parameter()]
    [string]$OutputDir = (Join-Path (Get-Location).Path 'openclaw-redacted')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Redaction rules ──────────────────────────────────────────────────
# Each rule: a regex that captures the key part and replaces the value.
# The replacements preserve structure so the redacted file stays valid.

$redactionRules = @(
    # JSON:  "key": "value"  or  "key": "value",
    @{
        Pattern     = '(?i)("(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password)")\s*:\s*"[^"]*"'
        Replacement = '$1: "[REDACTED]"'
    },
    # YAML:  key: value
    @{
        Pattern     = '(?im)^(\s*(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password)\s*:\s*)(.+)$'
        Replacement = '$1[REDACTED]'
    },
    # .env / INI:  KEY=value
    @{
        Pattern     = '(?im)^(\s*(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password)\s*=\s*)(.+)$'
        Replacement = '$1[REDACTED]'
    },
    # XML:  <Key>value</Key>
    @{
        Pattern     = '(?i)(<(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password)>)[^<]*(</)'
        Replacement = '$1[REDACTED]$2'
    },
    # Catch-all: long base64 / hex strings (≥40 chars) that are likely keys
    @{
        Pattern     = '(?<=[=:"\s])[A-Za-z0-9+/]{40,}={0,2}(?=["\s,\r\n]|$)'
        Replacement = '[REDACTED-LONG-TOKEN]'
    }
)

# ── Discover config files ────────────────────────────────────────────
$configExtensions = @('*.json', '*.yaml', '*.yml', '*.toml', '*.env', '*.config', '*.ini', '*.cfg', '*.xml')
$configFiles = @()

foreach ($ext in $configExtensions) {
    $configFiles += Get-ChildItem -Path $OpenClawRoot -Filter $ext -Recurse -ErrorAction SilentlyContinue
}

if ($configFiles.Count -eq 0) {
    Write-Host "No configuration files found in '$OpenClawRoot'." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($configFiles.Count) configuration file(s) to redact." -ForegroundColor Cyan

# ── Prepare output directory ─────────────────────────────────────────
if (Test-Path $OutputDir) {
    Write-Host "Output directory '$OutputDir' already exists. Files will be overwritten." -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ── Redact each file ────────────────────────────────────────────────
$stats = @{ Files = 0; Redactions = 0 }

foreach ($f in $configFiles) {
    $relativePath = $f.FullName.Substring($OpenClawRoot.Length).TrimStart('\', '/')
    $destPath     = Join-Path $OutputDir $relativePath
    $destDir      = Split-Path $destPath -Parent

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        Write-Host "  [SKIP] $relativePath (empty or unreadable)" -ForegroundColor DarkGray
        continue
    }

    $redacted = $content
    $fileRedactions = 0

    foreach ($rule in $redactionRules) {
        $matches = [regex]::Matches($redacted, $rule.Pattern)
        $fileRedactions += $matches.Count
        $redacted = [regex]::Replace($redacted, $rule.Pattern, $rule.Replacement)
    }

    # Write a header comment so the reader knows it's redacted
    $header = "# ── REDACTED by openclaw-redact.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ──`n"
    $header += "# Original: $relativePath`n"
    $header += "# Redactions applied: $fileRedactions`n`n"

    Set-Content -Path $destPath -Value ($header + $redacted) -Encoding UTF8 -NoNewline

    $icon = if ($fileRedactions -gt 0) { "[REDACTED]" } else { "[CLEAN]   " }
    $color = if ($fileRedactions -gt 0) { "Yellow" } else { "Green" }
    Write-Host "  $icon $relativePath ($fileRedactions redaction(s))" -ForegroundColor $color

    $stats.Files++
    $stats.Redactions += $fileRedactions
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══ Redaction complete ═══" -ForegroundColor Cyan
Write-Host "Files processed : $($stats.Files)"
Write-Host "Total redactions: $($stats.Redactions)"
Write-Host "Output directory: $OutputDir"
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "  1. Open the redacted files in Notepad (not type/cat) to review." -ForegroundColor Yellow
Write-Host "  2. Verify no secrets remain before sharing." -ForegroundColor Yellow
Write-Host "  3. Copy/paste ONLY from the redacted files, never from originals." -ForegroundColor Yellow
