#Requires -Version 5.1
# Hermes Home Server - keep running when laptop lid is closed
# Run as Administrator for full effect (lid-close setting)

param(
    [switch]$RestoreDefaults
)

$ErrorActionPreference = 'Stop'

# Re-launch as Admin if not elevated
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host 'Requesting Administrator (needed for lid-close setting)...'
    $elevatedArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath
    )
    if ($RestoreDefaults) {
        $elevatedArgs += '-RestoreDefaults'
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevatedArgs | Out-Null
    exit 0
}

Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Hermes Home Server - Power Settings'
Write-Host '==================================='
Write-Host ''

if ($RestoreDefaults) {
    powercfg /change standby-timeout-ac 30 | Out-Null
    powercfg /change hibernate-timeout-ac 180 | Out-Null
    powercfg /change monitor-timeout-ac 10 | Out-Null
    powercfg /change standby-timeout-dc 15 | Out-Null
    $subButtons = '4f971e89-eebd-4455-a8de-9e59040e7347'
    $lidClose   = '5ca83367-6e45-459f-a27d-476b1d01e936'
    powercfg /SETACVALUEINDEX SCHEME_CURRENT $subButtons $lidClose 1 2>$null | Out-Null
    powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subButtons $lidClose 1 2>$null | Out-Null
    powercfg /SETACTIVE SCHEME_CURRENT | Out-Null
    Write-Host 'Default power settings restored.'
    exit 0
}

$result = Ensure-ServerPower

Write-Host ''
Write-Host 'Done.'
Write-Host ''
Write-Host 'When plugged in (AC):'
Write-Host '  - Lid closed  -> PC stays awake, Hermes keeps running'
Write-Host '  - Screen may turn off after 10 min (normal)'
Write-Host '  - Sleep       -> disabled'
Write-Host ''
Write-Host 'On battery: sleep after 30 min (plug in for 24/7 server).'
Write-Host ''

if (-not $result.LidCloseOk) {
    Write-Host 'If lid-close was not applied, set manually:'
    Write-Host '  Settings -> System -> Power -> When I close the lid -> Do nothing'
    Write-Host ''
}
