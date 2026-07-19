#Requires -Version 5.1
# Hermes Home Server - uninstall

param(
    [switch]$KeepData
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
if (-not $KeepData) {
    $confirm = Read-Host 'Delete all data (memory, logs, backups)? [y/N]'
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host 'Cancelled.'
        exit 0
    }
}

Uninstall-HermesHome -KeepData:$KeepData
Write-Host 'Uninstall complete.'
Write-Host ''
