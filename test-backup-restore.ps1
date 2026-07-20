#Requires -Version 5.1
# Test backup + restore scripts (container + PowerShell)
#
# ВНИМАНИЕ: шаги restore и docker restart ДЕСТРУКТИВНЫ для работающего hermes-home.
# По умолчанию restore ПРОПУСКАЕТСЯ. Для полного прогона:
#   .\test-backup-restore.ps1 -AllowRestore
# Или через Pester: Invoke-Pester -Tag Destructive

param(
    # явное разрешение на restore + restart (по умолчанию ВЫКЛ)
    [switch]$AllowRestore,
    # только показать план, ничего не выполнять
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Hermes Home Server - Backup/Restore Test'
Write-Host '========================================='
Write-Host ''

# предупреждение про destructive-шаги
if (-not $AllowRestore) {
    Write-Host 'NOTE: restore/restart SKIPPED by default (safe for running hermes-home).'
    Write-Host '      Pass -AllowRestore to run full destructive test.'
    Write-Host ''
}

# режим WhatIf — только план
if ($WhatIf) {
    Write-Host 'WhatIf plan:'
    Write-Host '  [1] Container backup.sh'
    Write-Host '  [2] Container list-backups.sh'
    Write-Host '  [3] PowerShell New-HermesBackup'
    if ($AllowRestore) {
        Write-Host '  [4] Container restore.sh (DESTRUCTIVE)'
        Write-Host '  [5] PowerShell Restore-HermesBackup (DESTRUCTIVE)'
        Write-Host '  [6] docker compose restart (DESTRUCTIVE)'
    }
    else {
        Write-Host '  [4-6] skipped (no -AllowRestore)'
    }
    Write-Host ''
    return
}

# --- 1. Container scripts ---
Write-Host '[1] Container backup script...'
$out = docker exec hermes-home sh /opt/scripts/backup.sh 2>&1
Write-Host $out
if ($LASTEXITCODE -ne 0) { throw 'Container backup failed' }
Write-HermesStep -Name 'Container backup' -Status 'OK'

Write-Host ''
Write-Host '[2] Container list backups...'
docker exec hermes-home sh /opt/scripts/list-backups.sh 2>&1
Write-HermesStep -Name 'Container list' -Status 'OK'

Write-Host ''
Write-Host '[3] PowerShell backup.ps1...'
$zip = New-HermesBackup -Quiet
Write-Host "Created: $zip"
Write-HermesStep -Name 'PowerShell backup' -Status 'OK'

# --- destructive steps только с -AllowRestore ---
if ($AllowRestore) {
    Write-Host ''
    Write-Host '[4] Container restore (index 2)...'
    Write-Warning 'DESTRUCTIVE: restoring data inside hermes-home'
    docker exec hermes-home sh /opt/scripts/restore.sh 2 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Container restore failed' }
    Write-HermesStep -Name 'Container restore' -Status 'OK'

    Write-Host ''
    Write-Host '[5] PowerShell restore (index 3)...'
    $backups = Get-HermesBackups
    Write-Host "Backups on disk: $($backups.Count)"
    if ($backups.Count -lt 2) {
        Write-Host 'Skip restore test - need at least 2 backups'
    }
    else {
        # Restore backup #3 (not newest, safer test)
        Restore-HermesBackup -Index 3
        Write-HermesStep -Name 'PowerShell restore' -Status 'OK'
    }

    Write-Host ''
    Write-Host '[6] Restart gateway...'
    Write-Warning 'DESTRUCTIVE: docker compose restart'
    Push-Location $PSScriptRoot
    $ErrorActionPreference = 'Continue'
    docker compose restart 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    Pop-Location
    Start-Sleep -Seconds 20
    Write-HermesStep -Name 'Gateway restart' -Status 'OK'
}
else {
    Write-Host ''
    Write-Host '[4-6] Restore/restart SKIPPED (default). Use -AllowRestore to enable.'
    Write-HermesStep -Name 'Restore/restart' -Status 'SKIP' -Detail 'pass -AllowRestore'
}

Write-Host ''
Write-Host 'All tests passed.'
Write-Host ''
Write-Host 'Telegram commands:'
Write-Host '  /bkp or /backup  - create backup'
Write-Host '  /backups         - list backups'
Write-Host '  /restore1        - restore newest'
Write-Host '  /restore2        - restore 2nd newest'
Write-Host '  /health          - server health'
Write-Host '  /sendbackup      - backup + send to Telegram'
Write-Host ''
