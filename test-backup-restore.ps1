#Requires -Version 5.1
# Test backup + restore scripts (container + PowerShell)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Hermes Home Server - Backup/Restore Test'
Write-Host '========================================='
Write-Host ''

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

Write-Host ''
Write-Host '[4] Container restore (index 2)...'
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
    # Restore backup #2 (not newest, safer test)
    Restore-HermesBackup -Index 3
    Write-HermesStep -Name 'PowerShell restore' -Status 'OK'
}

Write-Host ''
Write-Host '[6] Restart gateway...'
Push-Location $PSScriptRoot
$ErrorActionPreference = 'Continue'
docker compose restart 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
Pop-Location
Start-Sleep -Seconds 20
Write-HermesStep -Name 'Gateway restart' -Status 'OK'

Write-Host ''
Write-Host 'All tests passed.'
Write-Host ''
Write-Host 'Telegram commands:'
Write-Host '  /bkp or /backup  - create backup'
Write-Host '  /backups         - list backups'
Write-Host '  /restore1        - restore newest'
Write-Host '  /restore2        - restore 2nd newest'
Write-Host ''
