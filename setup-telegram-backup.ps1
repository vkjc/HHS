#Requires -Version 5.1
# Enable /bkp /backup /backups /restore1-3 in Telegram

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Setup Telegram backup/restore commands'
Write-Host '========================================'
Write-Host ''

Ensure-TelegramBackupCommands

Push-Location $PSScriptRoot
docker compose restart
Pop-Location

Write-Host ''
Write-Host 'Wait 30 sec, then in Telegram:'
Write-Host ''
Write-Host '  /bkp       - backup'
Write-Host '  /backups   - list'
Write-Host '  /restore1  - restore newest'
Write-Host ''
