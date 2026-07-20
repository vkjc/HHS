#Requires -Version 5.1
# Hermes Home Server — обновление

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Hermes Home Server — Update'
Write-Host ''

# П3: об итоге обновления сообщаем владельцу в Telegram
try {
    Ensure-Docker -Quiet                            # убеждаемся, что Docker запущен
    Update-Hermes                                   # backup -> pull -> restart -> health check
    Send-TelegramMessage -Text 'Hermes: обновление прошло успешно, сервер работает.' | Out-Null
}
catch {
    # обновление сорвалось — владелец должен узнать сразу
    Send-TelegramMessage -Text "Hermes: ошибка обновления! $_" | Out-Null
    throw
}

Write-Host ''
