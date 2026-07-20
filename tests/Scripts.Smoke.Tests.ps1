#Requires -Version 5.1
# Smoke-тесты: скрипты на месте, LF у .sh, quick_commands в config (если есть)
# Недеструктивные — только чтение файлов проекта

# описание набора
Describe 'Scripts smoke' {
    # корень проекта
    BeforeAll {
        # родитель папки tests
        $script:Root = Split-Path -Parent $PSScriptRoot
    }

    # список ожидаемых PowerShell-скриптов (П7/П8/Ф6/Ф7 и базовые)
    Context 'PowerShell scripts exist' {
        # имена корневых скриптов
        $psScripts = @(
            'backup.ps1',
            'restore.ps1',
            'watchdog.ps1',
            'personalize.ps1',
            'check-models.ps1',
            'status.ps1',
            'install.ps1',
            'update.ps1',
            'modules\HermesHomeServer.psm1'
        )
        # проверяем каждый (<_> = элемент массива в заголовке Pester)
        It 'существует <_>' -ForEach $psScripts {
            # полный путь
            $path = Join-Path $script:Root $_
            # файл должен быть
            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }

    # shell-скрипты для контейнера
    Context 'Shell scripts exist' {
        # имена в scripts/
        $shScripts = @(
            'scripts\backup.sh',
            'scripts\restore.sh',
            'scripts\list-backups.sh',
            'scripts\health.sh',
            'scripts\send-backup.sh'
        )
        # каждый на месте
        It 'существует <_>' -ForEach $shScripts {
            $path = Join-Path $script:Root $_
            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }

    # LF endings у .sh (Docker/Alpine плохо переносит CRLF)
    Context 'Shell scripts use LF endings' {
        # все .sh в scripts/
        It 'файл <_> без CR (LF-only)' -ForEach @(
            'backup.sh',
            'restore.sh',
            'list-backups.sh',
            'health.sh',
            'send-backup.sh'
        ) {
            # полный путь
            $path = Join-Path $script:Root ("scripts\" + $_)
            # читаем байты
            $bytes = [System.IO.File]::ReadAllBytes($path)
            # ищем байт CR = 0x0D
            $hasCr = $false
            foreach ($b in $bytes) {
                if ($b -eq 13) { $hasCr = $true; break }
            }
            # CR недопустим
            $hasCr | Should -BeFalse -Because "$_ must use LF line endings for Linux container"
        }
    }

    # quick_commands в живом config (если файл есть)
    Context 'config.yaml quick_commands' {
        It 'содержит quick_commands (если config.yaml существует)' {
            # путь к конфигу
            $cfg = Join-Path $script:Root 'data\config.yaml'
            # если конфига нет — пропускаем (чистая установка)
            if (-not (Test-Path -LiteralPath $cfg)) {
                Set-ItResult -Skipped -Because 'data\config.yaml отсутствует'
                return
            }
            # читаем без вывода секретов (в yaml их обычно нет)
            $raw = Get-Content -LiteralPath $cfg -Raw
            # блок команд
            $raw | Should -Match '(?m)^quick_commands:'
            # базовый бэкап
            $raw | Should -Match 'bkp:'
            # Ф1
            $raw | Should -Match 'health:'
            # Ф3
            $raw | Should -Match 'sendbackup:'
        }
    }

    # watchdog и personalize — не пустые
    Context 'New feature scripts are non-empty' {
        It 'watchdog.ps1 содержит проверку здоровья' {
            $path = Join-Path $script:Root 'watchdog.ps1'
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match 'Test-HermesHealthy'
            $raw | Should -Match 'Send-TelegramMessage'
        }
        It 'personalize.ps1 пишет SOUL.md' {
            $path = Join-Path $script:Root 'personalize.ps1'
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match 'SOUL\.md'
            $raw | Should -Match 'Write-HermesTextFile'
        }
        It 'check-models.ps1 умеет авто-замену (Ф7)' {
            $path = Join-Path $script:Root 'check-models.ps1'
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match 'replacements'
            $raw | Should -Match 'openrouter'
        }
        It 'backup.sh поддерживает retention и sessions (П5/П6)' {
            $path = Join-Path $script:Root 'scripts\backup.sh'
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match 'BACKUP_RETENTION'
            $raw | Should -Match 'sessions'
            $raw | Should -Match 'BACKUP_PASSWORD'
        }
        It 'health.sh печатает gateway (Ф1)' {
            $path = Join-Path $script:Root 'scripts\health.sh'
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match 'gateway'
        }
        It 'send-backup.sh шлёт документ (Ф3)' {
            $path = Join-Path $script:Root 'scripts\send-backup.sh'
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match 'sendDocument'
        }
    }

    # модуль экспортирует ключевые функции
    Context 'Module exports' {
        BeforeAll {
            Import-Module (Join-Path $script:Root 'modules\HermesHomeServer.psm1') -Force
        }
        It 'экспортирует New-HermesBackup' {
            Get-Command New-HermesBackup -Module HermesHomeServer | Should -Not -BeNullOrEmpty
        }
        It 'экспортирует Send-TelegramMessage' {
            Get-Command Send-TelegramMessage -Module HermesHomeServer | Should -Not -BeNullOrEmpty
        }
        It 'экспортирует Ensure-WatchdogSchedule' {
            Get-Command Ensure-WatchdogSchedule -Module HermesHomeServer | Should -Not -BeNullOrEmpty
        }
    }
}
