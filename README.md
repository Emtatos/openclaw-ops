# openclaw-ops

Safe OpenClaw diagnostics, redaction, backup, and restore scripts.

These PowerShell scripts help you maintain, troubleshoot, and safely share your OpenClaw configuration without risking secret exposure.

---

## Scripts

### `scripts/openclaw-diag.ps1`

Collects environment and configuration health information — **without ever displaying secret values**.

- Shows OS, runtime, and directory structure
- Lists all configuration files with size and last-modified dates
- Audits config files for secret-looking keys (names only, never values)
- Tests network connectivity to Kraken APIs and GitHub
- Checks if OpenClaw processes are running
- Tails the most recent log file (with inline redaction)

```powershell
.\scripts\openclaw-diag.ps1
.\scripts\openclaw-diag.ps1 -OpenClawRoot "C:\OpenClaw"
```

### `scripts/openclaw-redact.ps1`

Creates a **sanitised copy** of all configuration files in `./openclaw-redacted/`. Original files are never modified.

Handles JSON, YAML, .env, INI, XML, and TOML formats. Catches API keys, passwords, tokens, connection strings, long base64 blobs, and more.

```powershell
.\scripts\openclaw-redact.ps1
.\scripts\openclaw-redact.ps1 -OpenClawRoot "C:\OpenClaw" -OutputDir "C:\safe-share"
```

### `scripts/openclaw-backup.ps1`

Creates a **timestamped backup** of all configuration files under `./openclaw-backups/`. Each backup includes a `_backup-manifest.json` with metadata.

```powershell
.\scripts\openclaw-backup.ps1
.\scripts\openclaw-backup.ps1 -OpenClawRoot "C:\OpenClaw" -Tag "before-upgrade"
```

### `scripts/openclaw-restore.ps1`

Restores configuration files from a backup. **Nothing is written automatically.** For every file the script:

1. Shows a line-by-line diff against the current file
2. Asks for explicit **Y/N confirmation**
3. Only writes if you type **Y**

```powershell
.\scripts\openclaw-restore.ps1 -BackupDir ".\openclaw-backups\2025-05-01_143000"
.\scripts\openclaw-restore.ps1 -BackupDir ".\openclaw-backups\2025-05-01_143000_pre-v2" -OpenClawRoot "C:\OpenClaw"
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

Detta skapar en mapp `./openclaw-redacted/` med saniterade kopior av alla konfigurationsfiler. Alla API-nycklar, lösenord, tokens och andra hemligheter ersätts med `[REDACTED]`.

### 2. Granska output i Notepad

Öppna de redakterade filerna **i Notepad** (eller annan textredigerare) — använd **inte** `type`, `cat` eller `Get-Content` i terminalen, eftersom terminalhistorik kan loggas.

```powershell
notepad .\openclaw-redacted\config.json
```

Kontrollera att inga hemligheter finns kvar. Sök efter strängar som ser ut som nycklar, lösenord eller tokens.

### 3. Klistra från redakterade filer

Kopiera text **enbart** från filerna i `./openclaw-redacted/`. Klistra aldrig in text direkt från originalfilerna.

### 4. Originalfiler stannar på din maskin

- Klipp **aldrig** och klistra från de riktiga konfigurationsfilerna
- Skicka **aldrig** originalfiler som bifogade filer
- Använd redact-skriptet varje gång — dina filer kan ha ändrats sedan sist
- Kör `openclaw-backup.ps1` **innan** du gör ändringar, så du kan rulla tillbaka

### Sammanfattning

| Steg | Kommando | Syfte |
|------|----------|-------|
| Redaktera | `.\scripts\openclaw-redact.ps1` | Skapar säker kopia |
| Granska | Öppna i Notepad | Verifiera att inga hemligheter syns |
| Klistra | Från `./openclaw-redacted/` | Dela med AI-assistent |
| Original | Stannar på din maskin | Lämnar aldrig din dator |

---

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform)
- No external modules required

## License

MIT
