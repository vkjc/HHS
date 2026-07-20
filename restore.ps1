#Requires -Version 5.1
# Hermes Home Server - restore from backup

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

$backups = Get-HermesBackups
if ($backups.Count -eq 0) {
    Write-Host 'No backups found.'
    exit 1
}

Write-Host ''
Write-Host 'Available backups (1 = newest):'
Write-Host ''
for ($i = 0; $i -lt $backups.Count; $i++) {
    $name = $backups[$i].BaseName
    Write-Host ("{0}`n{1}" -f ($i + 1), $name)
    if ($i -lt $backups.Count - 1) { Write-Host '' }
}
Write-Host ''

$choice = Read-Host 'Select number'
if ($choice -notmatch '^\d+$') {
    throw 'Enter a number.'
}

Restore-HermesBackup -Index ([int]$choice)
Write-Host ''
Write-Host 'Restore complete.'
Write-Host ''
