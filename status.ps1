#Requires -Version 5.1
# Hermes Home Server — статус

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

$s = Get-HermesStatus

Write-Host ''
Write-Host 'Hermes Home Server'
Write-Host ''
Write-Host ("Docker .............. {0}" -f $s.DockerStatus)
Write-Host ("Hermes .............. {0}" -f $s.HermesStatus)
Write-Host ("Telegram ............ {0}" -f $s.TelegramStatus)
Write-Host ("Memory .............. {0}" -f $s.MemoryOk)
Write-Host ("Logs ................ {0}" -f $s.LogsOk)
Write-Host ("Backups ............. {0}" -f $s.BackupCount)
Write-Host ("Disk Free ........... {0} GB" -f $s.DiskFreeGb)
Write-Host ("RAM Free ............ {0} GB" -f $s.RamFreeGb)
Write-Host ("Last Backup ......... {0}" -f $s.LastBackup)
Write-Host ("External Provider ... {0}" -f $s.ExternalProvider)
Write-Host ("Version ............. {0}" -f $s.Version)
Write-Host ''
