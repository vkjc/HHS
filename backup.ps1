#Requires -Version 5.1
# Hermes Home Server — резервная копия

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

$path = New-HermesBackup -Quiet:$Quiet
if (-not $Quiet) {
    Write-Host "Created: $path"
}
