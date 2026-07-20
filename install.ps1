#Requires -Version 5.1
# Hermes Home Server - idempotent install

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1'
Import-Module $modulePath -Force

Write-Host ''
Write-Host 'Hermes Home Server - Install'
Write-Host '============================'
Write-Host ''

$alreadyConfigured = Test-HermesConfigured
$dockerOk = Test-DockerRunning
$hermesOk = Test-HermesHealthy
$telegramOk = Test-TelegramConfigured
$backupTask = Get-ScheduledTask -TaskName 'HermesHomeServer-NightlyBackup' -ErrorAction SilentlyContinue

if ($alreadyConfigured -and $dockerOk -and $hermesOk -and $telegramOk -and $backupTask -and -not $Force) {
    Write-HermesStep -Name 'Docker' -Status 'OK'
    Write-HermesStep -Name 'Hermes' -Status 'OK'
    Write-HermesStep -Name 'Telegram' -Status 'OK'
    Write-HermesStep -Name 'Backup' -Status 'OK'
    Write-Host ''
    Write-Host 'Nothing to do.'
    exit 0
}

if (-not $alreadyConfigured -or $Force) {
    Write-Host 'Enter 4 settings:'
    Write-Host ''

    $botToken = Read-Host 'Telegram Bot Token'
    $userId = Read-Host 'Telegram User ID'
    $providerUrl = Read-Host 'LLM Provider URL'
    $apiKey = Read-Host 'API Key' -AsSecureString
    $apiKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey)
    )

    if (-not $botToken -or -not $userId -or -not $providerUrl -or -not $apiKeyPlain) {
        throw 'All 4 fields are required.'
    }

    $model = Get-DefaultModelForProvider -ProviderUrl $providerUrl
    $providerName = Get-ProviderDisplayName -ProviderUrl $providerUrl
    $baseUrl = $providerUrl.TrimEnd('/')
    if (-not ($baseUrl -match '/v1/?$')) { $baseUrl = "$baseUrl/v1" }

    Ensure-HermesDataDirs
    Set-HermesEnv -Values @{
        TELEGRAM_BOT_TOKEN     = $botToken
        TELEGRAM_ALLOWED_USERS = $userId
        OPENAI_BASE_URL        = $baseUrl
        OPENAI_API_KEY         = $apiKeyPlain
        HERMES_MODEL           = $model
        HERMES_PROVIDER_NAME   = $providerName
        BACKUP_RETENTION       = '30'
    }
    New-HermesConfig -ProviderUrl $baseUrl -Model $model
    Write-HermesStep -Name 'Telegram' -Status 'OK'
}
else {
    Write-HermesStep -Name 'Telegram' -Status 'OK'
}

Ensure-Docker
Ensure-HermesDataDirs
Ensure-Hermes
Ensure-BackupSchedule
Ensure-WatchdogSchedule
Ensure-TelegramBackupCommands

# Keep running when laptop lid is closed
Ensure-ServerPower

$backups = Get-HermesBackups
if ($backups.Count -eq 0) {
    New-HermesBackup -Quiet
}

Write-Host ''
Write-Host 'Install complete.'
Write-Host 'Check: .\status.ps1'
Write-Host 'Telegram: send your bot "hello".'
Write-Host ''
