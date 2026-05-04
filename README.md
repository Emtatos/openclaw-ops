# openclaw-ops

Safe OpenClaw diagnostics, redaction, backup, and restore scripts.

These PowerShell scripts help you maintain, troubleshoot, and safely share your OpenClaw configuration without risking secret exposure. All scripts default to `~/.openclaw` (`$env:USERPROFILE\.openclaw`) — you can run them directly from this repo without specifying a path. Use `-OpenClawRoot` only if your OpenClaw installation lives elsewhere.

---

## Scripts

### `scripts/openclaw-diag.ps1`

Collects environment and configuration health information — **without ever displaying secret values**.

- Shows OS, runtime, and directory structure
- Lists configuration files with size and last-modified dates (excludes `node_modules`, `logs`, `sessions`, `transcripts`, backup/redacted dirs, `.git`, `*.bak`, `*.clobbered`)
- Prioritizes known OpenClaw config files (`openclaw.json`, `exec-approvals.json`, `node.json`, etc.)
- Audits config files for secret-looking keys (names only, never values)
- Checks OpenClaw CLI status (`gateway status`, `nodes status`, `exec-policy show`) -- honestly reports `[FAIL]` when commands return errors
- Tests gateway port 18789 connectivity (primary gateway indicator)
- Checks Windows Scheduled Tasks (`OpenClaw Gateway`, `OpenClaw Node`) if available
- Process scan is informational (`[INFO]`) -- gateway often runs via `node.exe` as a scheduled task
- Optional network checks (GitHub, npm, OpenAI)
- Tails the most recent log file with **full-strength redaction** (same rules as redact/restore -- JSON-shaped secrets, `sk-*` tokens, YAML/INI/XML values are all caught)

```powershell
.\scripts\openclaw-diag.ps1
.\scripts\openclaw-diag.ps1 -OpenClawRoot "D:\my-openclaw"
```

### `scripts/openclaw-redact.ps1`

Creates a **sanitised copy** of all configuration files in `./openclaw-redacted/`. Original files are never modified. **Redacted files preserve their original format** — valid JSON stays valid JSON, valid YAML stays valid YAML. Metadata is written to a separate `_redaction-manifest.json`.

Handles JSON, YAML, .env, INI, XML, and TOML formats. Catches API keys, passwords, tokens, connection strings, long base64 blobs, and more.

```powershell
.\scripts\openclaw-redact.ps1
.\scripts\openclaw-redact.ps1 -OpenClawRoot "D:\my-openclaw" -OutputDir "C:\safe-share"
```

### `scripts/openclaw-backup.ps1`

Creates a **timestamped backup** of known OpenClaw configuration files under `./openclaw-backups/`. By default, only core config files are included:

- `openclaw.json`
- `exec-approvals.json`
- `node.json`
- `nodes\paired.json`
- `nodes\pending.json`
- `agents\main\agent\auth-profiles.json`

Use `-IncludeSessions` to also back up session files. Sessions, transcripts, logs, and temporary files are excluded by default.

```powershell
.\scripts\openclaw-backup.ps1
.\scripts\openclaw-backup.ps1 -Tag "before-upgrade"
.\scripts\openclaw-backup.ps1 -IncludeSessions -Tag "full-snapshot"
```

### `scripts/openclaw-restore.ps1`

Restores configuration files from a backup. **Nothing is written automatically.** For every file the script:

1. Shows a **redacted** line-by-line diff against the current file (secret values are never shown in terminal output)
2. Asks for explicit **Y/N confirmation**
3. Only writes the real file content to disk if you type **Y**

```powershell
.\scripts\openclaw-restore.ps1 -BackupDir ".\openclaw-backups\2025-05-01_143000"
.\scripts\openclaw-restore.ps1 -BackupDir ".\openclaw-backups\2025-05-01_143000_pre-v2" -OpenClawRoot "D:\my-openclaw"
```

---

## Typical workflow

```
1. .\scripts\openclaw-diag.ps1          # Check health
2. .\scripts\openclaw-backup.ps1        # Snapshot current config
3. .\scripts\openclaw-redact.ps1        # Create safe copy for sharing
4. (review ./openclaw-redacted/ in Notepad)
5. (share redacted files with support / AI assistant)
6. (make changes)
7. .\scripts\openclaw-restore.ps1 ...   # Roll back if needed
```

---

## Säker delning med AI-assistenter

> **Originalfiler med hemligheter ska aldrig lämna din maskin.**

Följ dessa steg innan du klistrar in konfiguration i ChatGPT, Copilot, Devin eller någon annan AI-assistent:

### 1. Kör redact-skriptet

```powershell
.\scripts\openclaw-redact.ps1
```

Detta skapar en mapp `./openclaw-redacted/` (under din `~/.openclaw`) med saniterade kopior av alla konfigurationsfiler. Alla API-nycklar, lösenord, tokens och andra hemligheter ersätts med `[REDACTED]`. **Filformatet bevaras** — JSON förblir giltig JSON.

### 2. Granska output i Notepad

Öppna de redakterade filerna **i Notepad** (eller annan textredigerare) — använd **inte** `type`, `cat` eller `Get-Content` i terminalen, eftersom terminalhistorik kan loggas.

```powershell
notepad "$env:USERPROFILE\.openclaw\openclaw-redacted\openclaw.json"
```

Kontrollera att inga hemligheter finns kvar. Sök efter strängar som ser ut som nycklar, lösenord eller tokens.

### 3. Klistra från redakterade filer

Kopiera text **enbart** från filerna i `openclaw-redacted/`. Klistra aldrig in text direkt från originalfilerna.

### 4. Originalfiler stannar på din maskin

- Klipp **aldrig** och klistra från de riktiga konfigurationsfilerna
- Skicka **aldrig** originalfiler som bifogade filer
- Använd redact-skriptet varje gång — dina filer kan ha ändrats sedan sist
- Kör `openclaw-backup.ps1` **innan** du gör ändringar, så du kan rulla tillbaka
- Restore-diff visar aldrig hemligheter i terminalen

### Sammanfattning

| Steg | Kommando | Syfte |
|------|----------|-------|
| Redaktera | `.\scripts\openclaw-redact.ps1` | Skapar säker kopia (giltig JSON/YAML) |
| Granska | Öppna i Notepad | Verifiera att inga hemligheter syns |
| Klistra | Från `openclaw-redacted/` | Dela med AI-assistent |
| Original | Stannar på din maskin | Lämnar aldrig din dator |

---

## Tests

Test fixtures and scripts live in `tests/`:

```powershell
# Test that redaction produces valid JSON and catches all secret fields
.\tests\test-redact.ps1

# Test that restore diff output never shows secret values
.\tests\test-restore-diff.ps1

# Test that diag log tail output never shows secret values
.\tests\test-diag-log.ps1

# Test diag status checks, config scope, and node_modules exclusion
.\tests\test-diag-status.ps1
```

---

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform)
- No external modules required

## Branch policy

Branch is deleted after merge.

## License

MIT
