# AGENTS.md

## Cursor Cloud specific instructions

Hermes Home Server is a **Windows-first PowerShell project** (`#Requires -Version 5.1`,
Task Scheduler, `$env:TEMP`, `icacls`). Its runtime "app" is a Docker container
(`nousresearch/hermes-agent:latest`) orchestrated by the root `*.ps1` scripts; the code
you develop/test here is the PowerShell module `modules/HermesHomeServer.psm1`, the
container shell scripts in `scripts/*.sh`, and the Pester tests in `tests/`.
See `TECHNICAL_SPEC.md` for the full architecture and the host command table.

On the Linux cloud VM everything runs under **PowerShell 7 (`pwsh`)**. Dev toolchain
(installed by the update script): `pwsh`, the `Pester` (5+/6) and `PSScriptAnalyzer`
PowerShell modules, and `openssl`.

### Tests
- Run: `TEMP=/tmp pwsh -File ./tests/Run-Tests.ps1` (add `-SkipIntegration` to skip the
  Docker/backup integration tests, `-Detailed` for verbose Pester output).
- `$env:TEMP` is unset on Linux but the module and tests rely on it. Interactive shells
  get `TEMP`/`TMP` from `~/.bashrc`; for one-off/non-login `pwsh` invocations prefix with
  `TEMP=/tmp` (as above), otherwise `Run-Tests.ps1` dies at the coverage `Join-Path`.
- **Two failures are expected on Linux and are not code bugs** (the suite passes on Windows):
  1. `New-HermesBackup ... шифрует .env в .env.enc` — `Compress-Archive` on Linux omits
     leading-dot hidden files (e.g. `.env.enc`) from the zip; non-dot files are fine.
  2. `Backup integration.PowerShell New-HermesBackup.создаёт zip на хосте` — needs a
     configured project. A clean checkout has no `data/`/`.env`, so the backup zip is empty
     and not created. Seed first with `Ensure-HermesDataDirs` + `New-HermesConfig` (see
     hello-world below) or run `install.ps1`.
- Container integration tests auto-skip when Docker / the `hermes-home` container is absent.

### Lint
- `pwsh -Command "Invoke-ScriptAnalyzer -Path . -Recurse"` — 0 errors. The ~194 warnings
  are stylistic/by-design (`PSAvoidUsingWriteHost` for CLI output, `Ensure-*` unapproved
  verbs); there is no analyzer settings file in the repo.

### Running the module (hello-world, no secrets needed)
```
TEMP=/tmp pwsh -NoProfile -Command '
  Import-Module ./modules/HermesHomeServer.psm1 -Force
  Ensure-HermesDataDirs
  New-HermesConfig -ProviderUrl "https://openrouter.ai/api/v1" -Model "openai/gpt-4o-mini"
  New-HermesBackup -Quiet   # writes backups/backup-*.zip
'
```
`data/` and `backups/` are gitignored, so this does not dirty the working tree.

### The Docker "app" (not runnable in cloud by default)
`docker compose up` starts the real Hermes agent, which requires live secrets in `.env`
(`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `OPENAI_BASE_URL`, `OPENAI_API_KEY`,
optionally `GROQ_API_KEY`). Docker is not installed here and no secrets are provided, so the
container is not part of the default dev loop — module dev/tests/lint cover the codebase.

### Gotchas
- `scripts/*.sh` must keep **LF** line endings (enforced by `.gitattributes` and a smoke
  test); they run inside the Alpine/Linux container and CRLF breaks them.
- `New-HermesConfig` and `Ensure-HermesDataDirs` are non-destructive: they never overwrite
  an existing `data/config.yaml` or user-edited wiki/skill files.
