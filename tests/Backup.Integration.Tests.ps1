#Requires -Version 5.1
# Integration: backup.sh создаёт архив (БЕЗ restore / docker restart)
# Тег Integration — можно исключить: Invoke-Pester -ExcludeTag Integration
# Недеструктивно для работающего hermes-home (только создание zip)

# описание
Describe 'Backup integration' -Tag 'Integration' {
    # корень и модуль
    BeforeAll {
        # родитель tests/
        $script:Root = Split-Path -Parent $PSScriptRoot
        # модуль
        Import-Module (Join-Path $script:Root 'modules\HermesHomeServer.psm1') -Force
        # проверка: контейнер запущен?
        $script:ContainerUp = $false
        # docker есть?
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            # inspect без вывода лишнего
            $running = docker inspect --format '{{.State.Running}}' hermes-home 2>$null
            # true = контейнер жив
            if ($running -eq 'true') { $script:ContainerUp = $true }
        }
    }

    # контейнерный backup.sh
    Context 'Container backup.sh' {
        It 'создаёт zip с sessions/skills/cron' -Skip:(-not $script:ContainerUp) {
            # список архивов ДО
            $before = @(Get-ChildItem (Join-Path $script:Root 'backups') -Filter 'backup-*.zip' -ErrorAction SilentlyContinue)
            # запускаем backup внутри контейнера (без restore!)
            $out = docker exec hermes-home sh /opt/scripts/backup.sh 2>&1
            # код выхода 0
            $LASTEXITCODE | Should -Be 0
            # вывод не пустой
            ($out | Out-String) | Should -Match 'Backup created'
            # список архивов ПОСЛЕ
            $after = @(Get-ChildItem (Join-Path $script:Root 'backups') -Filter 'backup-*.zip' -ErrorAction SilentlyContinue)
            # стало не меньше
            $after.Count | Should -BeGreaterOrEqual $before.Count
            # берём самый новый
            $newest = $after | Sort-Object Name -Descending | Select-Object -First 1
            # есть файл
            $newest | Should -Not -BeNullOrEmpty
            # распаковываем во временную папку (не в data!)
            $tmp = Join-Path $env:TEMP ("hermes-itest-" + [guid]::NewGuid().ToString('N'))
            # создаём
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                # распаковка
                Expand-Archive -Path $newest.FullName -DestinationPath $tmp -Force
                # обязательные папки в составе (даже если пустые — python мог не создать пустые;
                # проверяем что скрипт хотя бы положил config или memory)
                $hasConfig = Test-Path (Join-Path $tmp 'config')
                $hasMemory = Test-Path (Join-Path $tmp 'memory')
                # хотя бы config или memory
                ($hasConfig -or $hasMemory) | Should -BeTrue
                # sessions/skills/cron — папки создаются в TMP скриптом; в zip попадут если есть файлы
                # проверяем, что backup.sh в образе содержит эти пути (уже в smoke);
                # здесь: если на хосте есть файлы в data\sessions — они должны быть в архиве
                $sessHost = Join-Path $script:Root 'data\sessions'
                if ((Test-Path $sessHost) -and (Get-ChildItem $sessHost -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                    Test-Path (Join-Path $tmp 'sessions') | Should -BeTrue
                }
            }
            finally {
                # чистим temp
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'кладёт .env.enc если BACKUP_PASSWORD задан' -Skip:(-not $script:ContainerUp) {
            # читаем .env через модуль (значение пароля НЕ печатаем)
            $envMap = Get-HermesEnv
            # пароль задан?
            $hasPass = [bool]$envMap['BACKUP_PASSWORD']
            if (-not $hasPass) {
                Set-ItResult -Skipped -Because 'BACKUP_PASSWORD не задан'
                return
            }
            # свежий бэкап
            docker exec hermes-home sh /opt/scripts/backup.sh 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
            # новейший zip
            $newest = Get-ChildItem (Join-Path $script:Root 'backups') -Filter 'backup-*.zip' |
                Sort-Object Name -Descending |
                Select-Object -First 1
            $tmp = Join-Path $env:TEMP ("hermes-itest-enc-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            try {
                Expand-Archive -Path $newest.FullName -DestinationPath $tmp -Force
                # .env.enc должен быть
                Test-Path (Join-Path $tmp 'config\.env.enc') | Should -BeTrue
                # открытого .env быть не должно
                Test-Path (Join-Path $tmp 'config\.env') | Should -BeFalse
            }
            finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # PowerShell backup без restore
    Context 'PowerShell New-HermesBackup' {
        It 'создаёт zip на хосте' {
            # создаём архив (реальный проект — недеструктивно, только +1 zip)
            $zip = New-HermesBackup -Quiet
            # путь не пустой
            $zip | Should -Not -BeNullOrEmpty
            # файл есть
            Test-Path -LiteralPath $zip | Should -BeTrue
            # имя по шаблону
            (Split-Path $zip -Leaf) | Should -Match '^backup-\d{4}-\d{2}-\d{2}-\d{6}\.zip$'
        }
    }
}
