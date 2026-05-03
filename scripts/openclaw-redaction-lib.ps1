<#
.SYNOPSIS
    Shared redaction rules and helper functions used by openclaw-redact,
    openclaw-restore, and openclaw-diag.

.DESCRIPTION
    Dot-source this file to get $script:redactionRules and the
    Invoke-RedactText function.  All scripts use the same rule set
    so redaction strength is consistent everywhere.
#>

# -- Redaction rules --------------------------------------------------
# Each rule: a regex pattern and a replacement string.
# Rules are applied in order; earlier rules take priority.

$script:redactionRules = @(
    # JSON:  "key": "value"
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
    # Long base64/hex strings (>=40 chars) that are likely keys
    @{
        Pattern     = '(?<=[=:"\s])[A-Za-z0-9+/]{40,}={0,2}(?=["\s,\r\n]|$)'
        Replacement = '[REDACTED-LONG-TOKEN]'
    },
    # OpenAI-style sk-... tokens in free text (at least 10 chars after sk-)
    @{
        Pattern     = '\bsk-[A-Za-z0-9_]{10,}\b'
        Replacement = '[REDACTED-SK-TOKEN]'
    }
)

function Invoke-RedactText {
    <#
    .SYNOPSIS
        Applies all redaction rules to a string and returns the sanitised result.
    #>
    param([string]$Text)
    $result = $Text
    foreach ($rule in $script:redactionRules) {
        $result = [regex]::Replace($result, $rule.Pattern, $rule.Replacement)
    }
    return $result
}
