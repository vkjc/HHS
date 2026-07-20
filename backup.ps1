#Requires -Version 5.1
# Hermes Home Server — резервная копия

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

# П3: любую ошибку бэкапа сообщаем владельцу в Telegram —
# ночной запуск по расписанию иначе падает молча
try {
    $path = New-HermesBackup -Quiet:$Quiet          # создаём архив
    if (-not $Quiet) {
        Write-Host "Created: $path"                 # показываем путь при ручном запуске
    }
}
catch {
    # шлём уведомление и пробрасываем ошибку дальше (код выхода останется ненулевым)
    Send-TelegramMessage -Text "Hermes: ошибка резервного копирования! $_" | Out-Null
    throw
}
