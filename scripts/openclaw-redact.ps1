<#
.SYNOPSIS
    Redacts secrets from OpenClaw configuration files and writes
    sanitised copies to ./openclaw-redacted/.

.DESCRIPTION
    Scans configuration files for values that look like API keys,
    passwords, tokens, connection strings, etc. and replaces them
    with safe placeholder text.  Original files are NEVER modified.

    Redacted files keep their original format intact (valid JSON
    stays valid JSON, etc.).  Metadata is written to a separate
    _redaction-manifest.json file.

    The output folder (./openclaw-redacted/) can be opened in
    Notepad, reviewed, and then safely pasted into AI assistants
    or support tickets.

.PARAMETER OpenClawRoot
    Path to the OpenClaw installation directory.
    Defaults to $env:USERPROFILE\.openclaw.

.PARAMETER OutputDir
    Path where redacted copies are written.
    Defaults to ./openclaw-redacted (relative to OpenClawRoot).

.EXAMPLE
    .\openclaw-redact.ps1
    .\openclaw-redact.ps1 -OpenClawRoot "D:\my-openclaw" -OutputDir "C:\safe-share"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OpenClawRoot = (Join-Path $env:USERPROFILE '.openclaw'),

    [Parameter()]
    [string]$OutputDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OutputDir) {
    $OutputDir = Join-Path $OpenClawRoot 'openclaw-redacted'
}

# ── Redaction rules ──────────────────────────────────────────────────
# Each rule: a regex that captures the key part and replaces the value.
# The replacements preserve structure so the redacted file stays valid.

$script:redactionRules = @(
    # JSON:  "key": "value"  or  "key": "value",
    @{
        Pattern     = '(?i)("(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password|bot[_-]?token|key)")\s*:\s*"[^"]*"'
        Replacement = '$1: "[REDACTED]"'
    },
    # YAML:  key: value
    @{
        Pattern     = '(?im)^(\s*(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password|bot[_-]?token|key)\s*:\s*)(.+)$'
        Replacement = '$1[REDACTED]'
    },
    # .env / INI:  KEY=value
    @{
        Pattern     = '(?im)^(\s*(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password|bot[_-]?token|key)\s*=\s*)(.+)$'
        Replacement = '$1[REDACTED]'
    },
    # XML:  <Key>value</Key>
    @{
        Pattern     = '(?i)(<(?:api[_-]?key|api[_-]?secret|secret|password|pwd|token|passphrase|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|connection[_-]?string|credentials?|hmac|signing[_-]?key|webhook[_-]?secret|admin[_-]?password|db[_-]?password|bot[_-]?token|key)>)[^<]*(</)'
        Replacement = '$1[REDACTED]$2'
    },
    # Catch-all: long base64 / hex strings (>=40 chars) that are likely keys
    @{
        Pattern     = '(?<=[=:"\s])[A-Za-z0-9+/]{40,}={0,2}(?=["\s,\r\n]|$)'
        Replacement = '[REDACTED-LONG-TOKEN]'
    }
)

# ── Shared redaction function (also used by restore) ─────────────────
function Invoke-Redact {
    param([string]$Text)
    $result = $Text
    foreach ($rule in $script:redactionRules) {
        $result = [regex]::Replace($result, $rule.Pattern, $rule.Replacement)
    }
    return $result
}

# ── Discover config files ────────────────────────────────────────────
$configExtensions = @('*.json', '*.yaml', '*.yml', '*.toml', '*.env', '*.config', '*.ini', '*.cfg', '*.xml')
$configFiles = @()

foreach ($ext in $configExtensions) {
    $configFiles += Get-ChildItem -Path $OpenClawRoot -Filter $ext -Recurse -ErrorAction SilentlyContinue
}

# Exclude output dir and backup dirs from scan
$configFiles = $configFiles | Where-Object {
    $_.FullName -notlike "*openclaw-redacted*" -and
    $_.FullName -notlike "*openclaw-backups*"
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
$manifestEntries = @()

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

    foreach ($rule in $script:redactionRules) {
        $matches = [regex]::Matches($redacted, $rule.Pattern)
        $fileRedactions += $matches.Count
        $redacted = [regex]::Replace($redacted, $rule.Pattern, $rule.Replacement)
    }

    # Write redacted file WITHOUT any header — preserves original format
    Set-Content -Path $destPath -Value $redacted -Encoding UTF8 -NoNewline

    $manifestEntries += [PSCustomObject]@{
        File       = $relativePath
        Redactions = $fileRedactions
    }

    $icon = if ($fileRedactions -gt 0) { "[REDACTED]" } else { "[CLEAN]   " }
    $color = if ($fileRedactions -gt 0) { "Yellow" } else { "Green" }
    Write-Host "  $icon $relativePath ($fileRedactions redaction(s))" -ForegroundColor $color
}

# ── Write redaction manifest (separate file) ─────────────────────────
$manifest = @{
    Timestamp    = (Get-Date).ToUniversalTime().ToString('o')
    OpenClawRoot = $OpenClawRoot
    TotalFiles   = $manifestEntries.Count
    TotalRedactions = ($manifestEntries | Measure-Object -Property Redactions -Sum).Sum
    Files        = $manifestEntries | ForEach-Object {
        @{ File = $_.File; Redactions = $_.Redactions }
    }
}

$manifestPath = Join-Path $OutputDir '_redaction-manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══ Redaction complete ═══" -ForegroundColor Cyan
Write-Host "Files processed : $($manifestEntries.Count)"
Write-Host "Total redactions: $(($manifestEntries | Measure-Object -Property Redactions -Sum).Sum)"
Write-Host "Output directory: $OutputDir"
Write-Host "Manifest        : $manifestPath"
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "  1. Open the redacted files in Notepad (not type/cat) to review." -ForegroundColor Yellow
Write-Host "  2. Verify no secrets remain before sharing." -ForegroundColor Yellow
Write-Host "  3. Copy/paste ONLY from the redacted files, never from originals." -ForegroundColor Yellow
