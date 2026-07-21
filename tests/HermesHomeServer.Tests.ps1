#Requires -Version 5.1
# Unit-тесты модуля HermesHomeServer.psm1 (Pester 5+)
# Недеструктивные: работают в temp-каталогах, сеть (Telegram) — через Mock

# описание набора тестов модуля
Describe 'HermesHomeServer module' {
    # один раз перед всеми тестами: подключаем модуль
    BeforeAll {
        # корень проекта = родитель папки tests
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        # полный путь к файлу модуля
        $script:ModulePath = Join-Path $script:ProjectRoot 'modules\HermesHomeServer.psm1'
        # загружаем модуль заново (чтобы тесты видели актуальный код)
        Import-Module $script:ModulePath -Force
    }

    # перед каждым тестом — чистый временный «проект»
    BeforeEach {
        # уникальная папка под TestDrive (Pester сам чистит)
        $script:TestRoot = Join-Path $TestDrive ("proj-" + [guid]::NewGuid().ToString('N'))
        # создаём корень временного проекта
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        # создаём data/ как в настоящем проекте
        New-Item -ItemType Directory -Path (Join-Path $script:TestRoot 'data') -Force | Out-Null
        # создаём backups/
        New-Item -ItemType Directory -Path (Join-Path $script:TestRoot 'backups') -Force | Out-Null
        # пустой docker-compose.yml (на случай если mock сорвётся)
        Set-Content -Path (Join-Path $script:TestRoot 'docker-compose.yml') -Value 'services: {}' -Encoding ASCII
        # все функции модуля должны смотреть в temp, а не в живой проект
        # -ModuleName обязателен: иначе mock не перехватывает вызовы ИЗ модуля
        Mock Get-HermesProjectRoot { return $script:TestRoot } -ModuleName HermesHomeServer
    }

    # --- П2: запись UTF-8 без BOM ---
    Context 'Write-HermesTextFile (П2)' {
        # проверяем, что файл начинается не с BOM
        It 'пишет UTF-8 без BOM' {
            # путь к тестовому файлу
            $path = Join-Path $script:TestRoot 'nobom.txt'
            # пишем две строки через функцию модуля
            Write-HermesTextFile -Path $path -Lines @('alpha', 'beta')
            # читаем сырые байты
            $bytes = [System.IO.File]::ReadAllBytes($path)
            # файл не пустой
            $bytes.Length | Should -BeGreaterThan 0
            # BOM UTF-8 = EF BB BF — его быть не должно
            if ($bytes.Length -ge 3) {
                # собираем первые три байта как строку для сравнения
                $head = '{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]
                # BOM недопустим
                $head | Should -Not -Be 'EFBBBF'
            }
            # содержимое читается как ожидаемые строки
            $text = Get-Content -Path $path -Raw
            # первая строка есть
            $text | Should -Match 'alpha'
            # вторая строка есть
            $text | Should -Match 'beta'
        }
    }

    # --- парсинг .env ---
    Context 'Get-HermesEnv' {
        # простой KEY=value
        It 'читает ключи и игнорирует комментарии' {
            # путь к .env во временном корне
            $envPath = Join-Path $script:TestRoot '.env'
            # пишем .env без секретов продакшена — только тестовые значения
            Write-HermesTextFile -Path $envPath -Lines @(
                '# комментарий',
                'FOO=bar',
                '',
                'BAZ=qux'
            )
            # вызываем парсер
            $map = Get-HermesEnv
            # FOO распарсился
            $map['FOO'] | Should -Be 'bar'
            # BAZ распарсился
            $map['BAZ'] | Should -Be 'qux'
            # комментарий не стал ключом
            $map.ContainsKey('# комментарий') | Should -BeFalse
        }

        # нет файла — пустая таблица
        It 'возвращает пустую таблицу если .env нет' {
            # .env намеренно не создаём
            $map = Get-HermesEnv
            # тип — hashtable
            $map | Should -BeOfType ([hashtable])
            # ключей нет
            $map.Count | Should -Be 0
        }
    }

    # --- Set-HermesEnv ---
    Context 'Set-HermesEnv' {
        # обновление существующего ключа
        It 'обновляет существующий ключ и добавляет новый' {
            # исходный .env
            $envPath = Join-Path $script:TestRoot '.env'
            # две строки
            Write-HermesTextFile -Path $envPath -Lines @('A=1', 'B=2')
            # обновляем A и добавляем C
            Set-HermesEnv -Values @{ A = '9'; C = '3' }
            # читаем обратно
            $map = Get-HermesEnv
            # A обновлён
            $map['A'] | Should -Be '9'
            # B не тронут
            $map['B'] | Should -Be '2'
            # C добавлен
            $map['C'] | Should -Be '3'
        }
    }

    # --- П1: New-HermesConfig не затирает yaml ---
    Context 'New-HermesConfig (П1)' {
        # не перезаписывает существующий файл
        It 'не затирает существующий config.yaml' {
            # путь к конфигу
            $cfg = Join-Path $script:TestRoot 'data\config.yaml'
            # маркер, который не должен исчезнуть
            $marker = 'KEEP_ME_UNIQUE_MARKER_123'
            # пишем «живой» конфиг
            Write-HermesTextFile -Path $cfg -Lines @("model:", "  default: old-model", "# $marker")
            # вызываем создание конфига (должно выйти сразу)
            New-HermesConfig -ProviderUrl 'https://openrouter.ai/api/v1' -Model 'should-not-apply'
            # читаем файл
            $raw = Get-Content -Path $cfg -Raw
            # маркер на месте
            $raw | Should -Match $marker
            # старая модель не заменена
            $raw | Should -Match 'old-model'
        }

        # создаёт новый конфиг с quick_commands
        It 'создаёт config.yaml с quick_commands и OpenRouter fallback' {
            # конфига ещё нет
            $cfg = Join-Path $script:TestRoot 'data\config.yaml'
            # создаём для OpenRouter
            New-HermesConfig -ProviderUrl 'https://openrouter.ai/api/v1' -Model 'ignored'
            # файл появился
            Test-Path $cfg | Should -BeTrue
            # читаем
            $raw = Get-Content -Path $cfg -Raw
            # блок quick_commands (Ф1/Ф3 команды тоже)
            $raw | Should -Match '(?m)^quick_commands:'
            # команда bkp
            $raw | Should -Match 'bkp:'
            # команда health (Ф1)
            $raw | Should -Match 'health:'
            # команда sendbackup (Ф3)
            $raw | Should -Match 'sendbackup:'
            # wiki quick commands
            $raw | Should -Match 'wikistatus:'
            $raw | Should -Match 'wikisearch:'
            # STT через Groq Whisper
            $raw | Should -Match '(?m)^stt:'
            $raw | Should -Match 'provider: groq'
            # fallback OpenRouter (П1)
            $raw | Should -Match 'custom_providers:'
            # без BOM
            $bytes = [System.IO.File]::ReadAllBytes($cfg)
            $head = '{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]
            $head | Should -Not -Be 'EFBBBF'
        }
    }

    # --- провайдеры ---
    Context 'Get-DefaultModelForProvider / Get-ProviderDisplayName' {
        # модель для OpenRouter
        It 'подбирает модель OpenRouter' {
            Get-DefaultModelForProvider -ProviderUrl 'https://openrouter.ai/api/v1' | Should -Be 'openai/gpt-4o-mini'
        }
        # имя провайдера
        It 'возвращает DisplayName OpenRouter' {
            Get-ProviderDisplayName -ProviderUrl 'https://openrouter.ai/api/v1' | Should -Be 'OpenRouter'
        }
        # DeepSeek
        It 'подбирает модель DeepSeek' {
            Get-DefaultModelForProvider -ProviderUrl 'https://api.deepseek.com' | Should -Be 'deepseek-chat'
        }
    }

    # --- П3: Telegram mock ---
    Context 'Send-TelegramMessage (П3)' {
        # успешная отправка без реальной сети
        It 'шлёт через Invoke-RestMethod и возвращает True' {
            # поддельный .env с тестовыми (не боевыми) значениями
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=test-token-not-real',
                'TELEGRAM_ALLOWED_USERS=111,222'
            )
            # мокаем HTTP внутри модуля: сеть не трогаем
            Mock Invoke-RestMethod { return @{ ok = $true } } -ModuleName HermesHomeServer
            # вызываем
            $ok = Send-TelegramMessage -Text 'hello-test'
            # успех
            $ok | Should -BeTrue
            # Invoke-RestMethod вызван ровно один раз (из модуля)
            Should -Invoke Invoke-RestMethod -ModuleName HermesHomeServer -Times 1 -Exactly
        }

        # без токена — False, без сети
        It 'возвращает False если токена нет' {
            # пустой .env
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @('FOO=bar')
            # сеть мокаем на всякий случай
            Mock Invoke-RestMethod { throw 'should-not-call' } -ModuleName HermesHomeServer
            # вызов
            $ok = Send-TelegramMessage -Text 'nope'
            # ожидаем отказ
            $ok | Should -BeFalse
            # HTTP не вызывался
            Should -Invoke Invoke-RestMethod -ModuleName HermesHomeServer -Times 0 -Exactly
        }

        # ошибка сети не роняет скрипт
        It 'при ошибке API возвращает False' {
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=tok',
                'TELEGRAM_ALLOWED_USERS=1'
            )
            # имитируем сбой сети
            Mock Invoke-RestMethod { throw 'network down' } -ModuleName HermesHomeServer
            # не должно бросить исключение наружу
            $ok = Send-TelegramMessage -Text 'x'
            $ok | Should -BeFalse
        }
    }

    # --- П5 / П6 / П12 / Ф4: бэкап ---
    Context 'New-HermesBackup (П5/П6/П12/Ф4)' {
        # подготовка минимальных данных для архива
        BeforeEach {
            # подпапки data
            foreach ($d in @('memories', 'logs', 'sessions', 'skills', 'cron', 'wiki')) {
                # путь папки
                $p = Join-Path $script:TestRoot "data\$d"
                # создаём
                New-Item -ItemType Directory -Path $p -Force | Out-Null
                # кладём маркер-файл
                Set-Content -Path (Join-Path $p 'marker.txt') -Value $d -Encoding ASCII
            }
            # простой config.yaml
            Write-HermesTextFile -Path (Join-Path $script:TestRoot 'data\config.yaml') -Lines @('model:', '  default: test')
            # тестовый .env без реальных секретов
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=unit-test-token',
                'BACKUP_RETENTION=30'
            )
        }

        # состав архива: sessions/skills/cron
        It 'кладёт sessions/skills/cron в zip (П6)' {
            # создаём бэкап тихо
            $zip = New-HermesBackup -Quiet
            # zip существует
            Test-Path $zip | Should -BeTrue
            # распаковываем во временную папку
            $extract = Join-Path $script:TestRoot 'extract'
            Expand-Archive -Path $zip -DestinationPath $extract -Force
            # sessions
            Test-Path (Join-Path $extract 'sessions\marker.txt') | Should -BeTrue
            # skills
            Test-Path (Join-Path $extract 'skills\marker.txt') | Should -BeTrue
            # cron
            Test-Path (Join-Path $extract 'cron\marker.txt') | Should -BeTrue
            # memory (переименовано из memories)
            Test-Path (Join-Path $extract 'memory\marker.txt') | Should -BeTrue
        }

        # wiki входит в backup round-trip
        It 'кладёт wiki в zip (LLM Wiki)' {
            # создаём бэкап
            $zip = New-HermesBackup -Quiet
            # распаковка
            $extract = Join-Path $script:TestRoot 'extract-wiki'
            Expand-Archive -Path $zip -DestinationPath $extract -Force
            # маркер wiki на месте
            Test-Path (Join-Path $extract 'wiki\marker.txt') | Should -BeTrue
        }

        # retention: оставляем только N архивов
        It 'ротация по BACKUP_RETENTION (П5)' {
            # retention = 2
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=unit-test-token',
                'BACKUP_RETENTION=2'
            )
            # создаём три бэкапа подряд (имена по секундам)
            $z1 = New-HermesBackup -Quiet
            # небольшая пауза, чтобы метка времени отличалась
            Start-Sleep -Seconds 1
            $z2 = New-HermesBackup -Quiet
            Start-Sleep -Seconds 1
            $z3 = New-HermesBackup -Quiet
            # считаем zip в backups
            $all = Get-ChildItem (Join-Path $script:TestRoot 'backups') -Filter 'backup-*.zip'
            # должно остаться не больше 2
            $all.Count | Should -Be 2
            # самый новый на месте
            Test-Path $z3 | Should -BeTrue
        }

        # зеркало на другой путь
        It 'копирует архив в BACKUP_MIRROR_DIR (Ф4)' {
            # папка-зеркало
            $mirror = Join-Path $script:TestRoot 'mirror'
            # .env с зеркалом
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=unit-test-token',
                "BACKUP_MIRROR_DIR=$mirror"
            )
            # бэкап
            $zip = New-HermesBackup -Quiet
            # имя файла
            $leaf = Split-Path $zip -Leaf
            # копия в зеркале
            Test-Path (Join-Path $mirror $leaf) | Should -BeTrue
        }

        # шифрование .env если есть openssl и пароль
        It 'шифрует .env в .env.enc при BACKUP_PASSWORD (П12)' -Skip:(-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
            # пароль только для unit-теста (не боевой секрет)
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=unit-test-token',
                'BACKUP_PASSWORD=unit-test-password'
            )
            # бэкап
            $zip = New-HermesBackup -Quiet
            # распаковка
            $extract = Join-Path $script:TestRoot 'extract-enc'
            Expand-Archive -Path $zip -DestinationPath $extract -Force
            # .env.enc должен быть
            Test-Path (Join-Path $extract 'config\.env.enc') | Should -BeTrue
            # открытого .env в архиве быть не должно
            Test-Path (Join-Path $extract 'config\.env') | Should -BeFalse
        }

        # P1: state.db и auth.json попадают в архив
        It 'кладёт state.db и auth.json в zip если есть' {
            # маркер state.db
            Set-Content -Path (Join-Path $script:TestRoot 'data\state.db') -Value 'db' -Encoding ASCII
            # маркер auth.json
            Set-Content -Path (Join-Path $script:TestRoot 'data\auth.json') -Value '{}' -Encoding ASCII
            # бэкап
            $zip = New-HermesBackup -Quiet
            # распаковка
            $extract = Join-Path $script:TestRoot 'extract-state'
            Expand-Archive -Path $zip -DestinationPath $extract -Force
            # оба файла в config/
            Test-Path (Join-Path $extract 'config\state.db') | Should -BeTrue
            Test-Path (Join-Path $extract 'config\auth.json') | Should -BeTrue
        }
    }

    # --- P0: Get-HermesBackups — Index 1 = newest ---
    Context 'Get-HermesBackups (P0 newest-first)' {
        It 'Index 1 = самый новый архив' {
            # создаём три zip с разными LastWriteTime
            $dir = Join-Path $script:TestRoot 'backups'
            $old = Join-Path $dir 'backup-2020-01-01-000000.zip'
            $mid = Join-Path $dir 'backup-2021-01-01-000000.zip'
            $new = Join-Path $dir 'backup-2022-01-01-000000.zip'
            # минимальный валидный zip через Compress-Archive
            $tmpOld = Join-Path $script:TestRoot 't-old'
            $tmpMid = Join-Path $script:TestRoot 't-mid'
            $tmpNew = Join-Path $script:TestRoot 't-new'
            New-Item -ItemType Directory -Path $tmpOld, $tmpMid, $tmpNew -Force | Out-Null
            Set-Content (Join-Path $tmpOld 'a.txt') 'old' -Encoding ASCII
            Set-Content (Join-Path $tmpMid 'a.txt') 'mid' -Encoding ASCII
            Set-Content (Join-Path $tmpNew 'a.txt') 'new' -Encoding ASCII
            Compress-Archive -Path (Join-Path $tmpOld '*') -DestinationPath $old -Force
            Compress-Archive -Path (Join-Path $tmpMid '*') -DestinationPath $mid -Force
            Compress-Archive -Path (Join-Path $tmpNew '*') -DestinationPath $new -Force
            # выставляем время явно (Name-сортировка ascending дала бы old первым)
            (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-3)
            (Get-Item $mid).LastWriteTime = (Get-Date).AddDays(-2)
            (Get-Item $new).LastWriteTime = (Get-Date).AddDays(-1)
            # список
            $list = Get-HermesBackups
            # минимум 3
            $list.Count | Should -BeGreaterOrEqual 3
            # Index 1 (первый элемент) = newest
            $list[0].Name | Should -Be 'backup-2022-01-01-000000.zip'
        }
    }

    # --- Ensure-HermesDataDirs ---
    Context 'Ensure-HermesDataDirs' {
        It 'создаёт sessions/skills/cron/backups' {
            # вызываем
            Ensure-HermesDataDirs
            # sessions
            Test-Path (Join-Path $script:TestRoot 'data\sessions') | Should -BeTrue
            # skills
            Test-Path (Join-Path $script:TestRoot 'data\skills') | Should -BeTrue
            # cron
            Test-Path (Join-Path $script:TestRoot 'data\cron') | Should -BeTrue
            # backups
            Test-Path (Join-Path $script:TestRoot 'backups') | Should -BeTrue
        }
        It 'создаёт data/wiki подкаталоги' {
            # вызываем
            Ensure-HermesDataDirs
            # wiki root
            Test-Path (Join-Path $script:TestRoot 'data\wiki') | Should -BeTrue
            # raw
            Test-Path (Join-Path $script:TestRoot 'data\wiki\raw') | Should -BeTrue
            # pages/entities
            Test-Path (Join-Path $script:TestRoot 'data\wiki\pages\entities') | Should -BeTrue
        }

        It 'сеет wiki stubs и skill из templates/' {
            # вызываем (шаблоны берутся из реального репо рядом с modules/)
            Ensure-HermesDataDirs
            # SCHEMA из templates/wiki
            Test-Path (Join-Path $script:TestRoot 'data\wiki\SCHEMA.md') | Should -BeTrue
            # index
            Test-Path (Join-Path $script:TestRoot 'data\wiki\index.md') | Should -BeTrue
            # overview
            Test-Path (Join-Path $script:TestRoot 'data\wiki\pages\overview.md') | Should -BeTrue
            # skill wiki-llm
            Test-Path (Join-Path $script:TestRoot 'data\skills\research\wiki-llm\SKILL.md') | Should -BeTrue
            # повторный вызов не затирает правки пользователя
            $schema = Join-Path $script:TestRoot 'data\wiki\SCHEMA.md'
            Set-Content -LiteralPath $schema -Value 'custom-schema' -Encoding UTF8
            Ensure-HermesDataDirs
            (Get-Content -LiteralPath $schema -Raw).Trim() | Should -Be 'custom-schema'
        }
    }

    # --- Ф1/Ф3: дописывание quick_commands ---
    Context 'Ensure-TelegramBackupCommands (Ф1/Ф3)' {
        # копируем скрипты в temp (функция читает из project scripts/)
        BeforeEach {
            # папка scripts во временном корне
            $scripts = Join-Path $script:TestRoot 'scripts'
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            # минимальные заглушки .sh
            foreach ($n in @('backup.sh', 'list-backups.sh', 'restore.sh', 'health.sh', 'send-backup.sh', 'wiki-status.sh', 'wiki-search.sh')) {
                Set-Content -Path (Join-Path $scripts $n) -Value '#!/bin/sh' -Encoding ASCII
            }
        }

        It 'дописывает health и sendbackup в существующий quick_commands' {
            # конфиг с bkp, но без health/sendbackup
            $cfg = Join-Path $script:TestRoot 'data\config.yaml'
            Write-HermesTextFile -Path $cfg -Lines @(
                'model:',
                '  default: x',
                'quick_commands:',
                '  bkp:',
                '    type: exec',
                '    command: BACKUP_SKIP_SKILLS=1 sh /opt/scripts/backup.sh',
                '  restore1:',
                '    type: exec',
                '    command: sh /opt/scripts/restore.sh 1'
            )
            # вызываем
            $result = Ensure-TelegramBackupCommands -Quiet
            # успех
            $result | Should -BeTrue
            # читаем
            $raw = Get-Content -Path $cfg -Raw
            # health появился
            $raw | Should -Match '(?m)^\s*health:'
            # sendbackup появился
            $raw | Should -Match '(?m)^\s*sendbackup:'
            # wiki commands
            $raw | Should -Match '(?m)^\s*wikistatus:'
            $raw | Should -Match '(?m)^\s*wikisearch:'
        }
    }

    # --- Test-HermesConfigured ---
    Context 'Test-HermesConfigured' {
        It 'True когда все обязательные ключи есть' {
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=t',
                'TELEGRAM_ALLOWED_USERS=1',
                'OPENAI_BASE_URL=https://example.com/v1',
                'OPENAI_API_KEY=k'
            )
            Test-HermesConfigured | Should -BeTrue
        }
        It 'False когда ключа не хватает' {
            Write-HermesTextFile -Path (Join-Path $script:TestRoot '.env') -Lines @(
                'TELEGRAM_BOT_TOKEN=t'
            )
            Test-HermesConfigured | Should -BeFalse
        }
    }

    # --- Write-HermesStep формат ---
    Context 'Write-HermesStep' {
        It 'печатает статус без исключения' {
            # просто не должно упасть
            { Write-HermesStep -Name 'Test' -Status 'OK' -Detail 'unit' } | Should -Not -Throw
        }
    }
}
