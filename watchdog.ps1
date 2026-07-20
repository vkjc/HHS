#Requires -Version 5.1
# П8 + Ф9: watchdog — проверка Hermes каждые 15 минут

$ErrorActionPreference = 'Stop'
# подключаем общий модуль
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

# каталог логов
$logDir = Join-Path $PSScriptRoot 'data\logs'
# файл лога watchdog
$logFile = Join-Path $logDir 'watchdog.log'
# создаём папку логов при необходимости
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# метка времени для записи
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# пишем строку в лог
function Write-WatchLog {
    param([string]$Message)
    Add-Content -Path $logFile -Value "$now $Message"
}

try {
    # убеждаемся, что Docker запущен
    if (-not (Test-DockerRunning)) {
        Write-WatchLog 'Docker not running - trying to start Desktop'
        Ensure-Docker -Quiet
    }

    # П8: если контейнер не healthy - поднимаем и уведомляем
    if (-not (Test-HermesHealthy)) {
        Write-WatchLog 'Hermes unhealthy - restarting'
        Push-Location $PSScriptRoot
        try {
            docker compose up -d 2>&1 | Out-Null
        }
        finally {
            Pop-Location
        }
        # ждём до 2 минут
        $deadline = (Get-Date).AddMinutes(2)
        $ok = $false
        while ((Get-Date) -lt $deadline) {
            if (Test-HermesHealthy) { $ok = $true; break }
            Start-Sleep -Seconds 5
        }
        if ($ok) {
            Write-WatchLog 'Hermes restarted OK'
            Send-TelegramMessage -Text 'Hermes: контейнер был недоступен, watchdog поднял его снова.' | Out-Null
        }
        else {
            Write-WatchLog 'Hermes restart FAILED'
            Send-TelegramMessage -Text 'Hermes: watchdog не смог поднять контейнер! Проверьте Docker Desktop.' | Out-Null
        }
    }
    else {
        Write-WatchLog 'Hermes OK'
    }

    # Ф9: алерт, если на системном диске меньше 10 ГБ свободно
    $drive = (Get-Item $PSScriptRoot).PSDrive.Name
    if (-not $drive) { $drive = 'C' }
    $disk = Get-PSDrive -Name $drive -ErrorAction SilentlyContinue
    if ($disk) {
        $freeGb = [math]::Round($disk.Free / 1GB, 1)
        if ($freeGb -lt 10) {
            Write-WatchLog ("Low disk: {0} GB free on {1}:" -f $freeGb, $drive)
            $msg = 'Hermes: мало места на диске ' + $drive + ': - свободно ' + $freeGb + ' ГБ (порог 10 ГБ).'
            Send-TelegramMessage -Text $msg | Out-Null
        }
    }
}
catch {
    Write-WatchLog "ERROR: $_"
    Send-TelegramMessage -Text ('Hermes: ошибка watchdog! ' + $_) | Out-Null
}
