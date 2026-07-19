#Requires -Version 5.1
# Hermes Home Server — обновление

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Hermes Home Server — Update'
Write-Host ''

Ensure-Docker -Quiet
Update-Hermes

Write-Host ''
