# Hermes Home Server — общие функции PowerShell

function Get-HermesProjectRoot {
    # Возвращает корень проекта (папка с docker-compose.yml)
    $root = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path (Join-Path $root 'docker-compose.yml'))) {
        throw 'docker-compose.yml not found. Run scripts from project root.'
    }
    return $root
}

function Write-HermesStep {
    param(
        [string]$Name,
        [ValidateSet('OK', 'FAIL', 'SKIP', 'WORK')]
        [string]$Status,
        [string]$Detail = ''
    )
    # Печатает строку статуса в формате «Компонент...........OK»
    $dots = '.' * [Math]::Max(1, 18 - $Name.Length)
    $line = "{0}{1} {2}" -f $Name, $dots, $Status
    if ($Detail) { $line += " ($Detail)" }
    Write-Host $line
}

function Test-DockerInstalled {
    # Проверяет, установлен ли Docker CLI
    return [bool](Get-Command docker -ErrorAction SilentlyContinue)
}

function Test-DockerRunning {
    # Проверяет, отвечает ли Docker daemon
    if (-not (Test-DockerInstalled)) { return $false }
    docker info *> $null
    return $LASTEXITCODE -eq 0
}

function Ensure-Docker {
    param([switch]$Quiet)

    # Шаг 1: установка Docker Desktop через winget (если нет)
    if (-not (Test-DockerInstalled)) {
        if (-not $Quiet) { Write-HermesStep -Name 'Docker' -Status 'WORK' -Detail 'install' }
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw 'Docker is not installed and winget is unavailable. Install Docker Desktop manually.'
        }
        winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to install Docker Desktop via winget.'
        }
    }

    # Шаг 2: запуск Docker Desktop (если daemon не отвечает)
    if (-not (Test-DockerRunning)) {
        if (-not $Quiet) { Write-HermesStep -Name 'Docker' -Status 'WORK' -Detail 'start' }
        $dockerDesktop = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerDesktop) {
            Start-Process -FilePath $dockerDesktop | Out-Null
        }
        $deadline = (Get-Date).AddMinutes(5)
        while ((Get-Date) -lt $deadline) {
            if (Test-DockerRunning) { break }
            Start-Sleep -Seconds 5
        }
    }

    if (-not (Test-DockerRunning)) {
        throw 'Docker did not start within 5 minutes. Open Docker Desktop manually and retry.'
    }

    if (-not $Quiet) { Write-HermesStep -Name 'Docker' -Status 'OK' }
    return $true
}

function Write-HermesTextFile {
    param(
        [string]$Path,      # куда писать файл
        [string[]]$Lines    # строки содержимого
    )
    # ФИКС (П2): Set-Content -Encoding UTF8 в PowerShell 5.1 пишет BOM,
    # из-за чего docker compose и YAML-парсер могут не прочитать файл.
    # Пишем UTF-8 строго БЕЗ BOM через .NET.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $utf8NoBom)
}

function Get-HermesEnv {
    # Читает .env как hashtable
    $root = Get-HermesProjectRoot
    $envPath = Join-Path $root '.env'
    $result = @{}
    if (-not (Test-Path $envPath)) { return $result }
    Get-Content $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line -match '^([^=]+)=(.*)$') {
            $result[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $result
}

function Set-HermesEnv {
    param([hashtable]$Values)

    # Записывает или обновляет ключи в .env
    $root = Get-HermesProjectRoot
    $envPath = Join-Path $root '.env'
    $templatePath = Join-Path $root '.env.template'
    $lines = @()

    if (Test-Path $envPath) {
        $lines = Get-Content $envPath
    }
    elseif (Test-Path $templatePath) {
        $lines = Get-Content $templatePath
    }

    $existingKeys = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^([^=#]+)=') {
            $key = $Matches[1].Trim()
            $existingKeys[$key] = $i
            if ($Values.ContainsKey($key)) {
                $lines[$i] = "$key=$($Values[$key])"
                $Values.Remove($key) | Out-Null
            }
        }
    }

    foreach ($pair in $Values.GetEnumerator()) {
        $lines += "$($pair.Key)=$($pair.Value)"
    }

    # запись в UTF-8 без BOM (П2), иначе docker compose может не увидеть первый ключ
    Write-HermesTextFile -Path $envPath -Lines $lines
}

function Get-DefaultModelForProvider {
    param([string]$ProviderUrl)

    # Подбирает модель по умолчанию по URL провайдера
    $url = $ProviderUrl.ToLowerInvariant()
    if ($url -match 'openrouter') { return 'openai/gpt-4o-mini' }
    if ($url -match 'deepseek') { return 'deepseek-chat' }
    if ($url -match 'groq') { return 'llama-3.3-70b-versatile' }
    if ($url -match 'moonshot|kimi') { return 'moonshot-v1-8k' }
    if ($url -match 'google|generativelanguage|gemini') { return 'gemini-2.0-flash' }
    if ($url -match 'anthropic') { return 'claude-3-5-sonnet-20241022' }
    return 'gpt-4o-mini'
}

function Get-ProviderDisplayName {
    param([string]$ProviderUrl)

    # Человекочитаемое имя провайдера для status.ps1
    $url = $ProviderUrl.ToLowerInvariant()
    if ($url -match 'openrouter') { return 'OpenRouter' }
    if ($url -match 'deepseek') { return 'DeepSeek' }
    if ($url -match 'groq') { return 'Groq' }
    if ($url -match 'moonshot|kimi') { return 'Kimi' }
    if ($url -match 'google|generativelanguage|gemini') { return 'Gemini' }
    if ($url -match 'anthropic') { return 'Claude' }
    if ($url -match 'openai\.com') { return 'OpenAI' }
    try {
        $hostName = ([Uri]$ProviderUrl).Host
        $short = $hostName -replace '^api\.', '' -replace '\..*$', ''
        if ($short.Length -gt 0) {
            return ($short.Substring(0, 1).ToUpper() + $short.Substring(1))
        }
    }
    catch { }
    return 'Custom'
}

function New-HermesConfig {
    param(
        [string]$ProviderUrl,
        [string]$Model
    )

    # Создаёт config.yaml для Hermes без интерактивного мастера
    $root = Get-HermesProjectRoot
    $configPath = Join-Path $root 'data\config.yaml'

    # ФИКС (П1): если config.yaml уже существует — НЕ трогаем его.
    # Иначе install.ps1 -Force затирал бы рабочий конфиг
    # (fallback-цепочку моделей, quick-команды и т.д.).
    if (Test-Path $configPath) {
        Write-Host 'config.yaml уже существует — оставляем как есть.'
        return
    }

    $baseUrl = $ProviderUrl.TrimEnd('/')
    if (-not $baseUrl.EndsWith('/v1')) {
        if ($baseUrl -match '/v1/?$') { $baseUrl = $baseUrl.TrimEnd('/') }
        else { $baseUrl = "$baseUrl/v1" }
    }

    # ФИКС (П1): для OpenRouter добавляем блок custom_providers с цепочкой
    # бесплатных моделей — OpenRouter сам переключится на следующую при сбое.
    $fallbackBlock = ''
    if ($baseUrl -match 'openrouter') {
        # для OpenRouter основной моделью ставим первую из бесплатной цепочки
        $Model = 'nvidia/nemotron-3-super-120b-a12b:free'
        $fallbackBlock = @"

# Дополнительные параметры запроса к OpenRouter
custom_providers:
  # запись сопоставляется с моделью выше по одинаковому base_url
  - name: openrouter-free
    base_url: $baseUrl
    # extra_body добавляется в тело каждого запроса chat/completions
    extra_body:
      # OpenRouter сам переключится на следующую модель из списка
      # при ошибке основной (лимит 429, даунтайм, модерация)
      models:
        - nvidia/nemotron-3-super-120b-a12b:free
        - openai/gpt-oss-20b:free
        - google/gemma-4-31b-it:free
"@
    }

    $yaml = @"
model:
  provider: custom
  default: $Model
  base_url: $baseUrl
$fallbackBlock
gateway:
  platforms:
    telegram:
      enabled: true

tool_loop_guardrails:
  hard_stop_enabled: true
  hard_stop_after:
    exact_failure: 5
    idempotent_no_progress: 5

terminal:
  backend: local

quick_commands:
  bkp:
    type: exec
    command: sh /opt/scripts/backup.sh
  backup:
    type: exec
    command: sh /opt/scripts/backup.sh
  backups:
    type: exec
    command: sh /opt/scripts/list-backups.sh
  restore1:
    type: exec
    command: sh /opt/scripts/restore.sh 1
  restore2:
    type: exec
    command: sh /opt/scripts/restore.sh 2
  restore3:
    type: exec
    command: sh /opt/scripts/restore.sh 3
  health:
    type: exec
    command: sh /opt/scripts/health.sh
  sendbackup:
    type: exec
    command: sh /opt/scripts/send-backup.sh
"@

    # запись в UTF-8 без BOM (П2), иначе YAML-парсер может споткнуться
    Write-HermesTextFile -Path $configPath -Lines ($yaml -split "`r?`n")
}

function Test-HermesConfigured {
    # Проверяет, что .env содержит все обязательные поля
    $env = Get-HermesEnv
    $required = @('TELEGRAM_BOT_TOKEN', 'TELEGRAM_ALLOWED_USERS', 'OPENAI_BASE_URL', 'OPENAI_API_KEY')
    foreach ($key in $required) {
        if (-not $env[$key]) { return $false }
    }
    return $true
}

function Ensure-HermesDataDirs {
    # Создаёт структуру каталогов в data/
    $root = Get-HermesProjectRoot
    $dirs = @(
        'data\memories',
        'data\logs',
        'data\sessions',
        'data\skills',
        'data\cron',
        'backups'
    )
    foreach ($dir in $dirs) {
        $path = Join-Path $root $dir
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Ensure-Hermes {
    param([switch]$Quiet)

    # Поднимает контейнер Hermes через docker compose
    $root = Get-HermesProjectRoot
    Push-Location $root
    try {
        if (-not $Quiet) { Write-HermesStep -Name 'Hermes' -Status 'WORK' -Detail 'pull' }
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        docker compose pull 2>&1 | Out-Null
        if (-not $Quiet) { Write-HermesStep -Name 'Hermes' -Status 'WORK' -Detail 'start' }
        docker compose up -d 2>&1 | Out-Null
        $ErrorActionPreference = $prevEap
        if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
        if (-not $Quiet) { Write-HermesStep -Name 'Hermes' -Status 'OK' }
    }
    finally {
        Pop-Location
    }
}

function Test-HermesHealthy {
    # Проверяет healthcheck контейнера
    $status = docker inspect --format '{{.State.Health.Status}}' hermes-home 2>$null
    if ($status -eq 'healthy') { return $true }
    $running = docker inspect --format '{{.State.Running}}' hermes-home 2>$null
    return ($running -eq 'true')
}

function Test-TelegramConfigured {
    # Проверяет наличие Telegram-токена в .env
    $env = Get-HermesEnv
    return [bool]($env['TELEGRAM_BOT_TOKEN'] -and $env['TELEGRAM_ALLOWED_USERS'])
}

function Get-HermesStatus {
    # Собирает полный статус для status.ps1
    $root = Get-HermesProjectRoot
    $env = Get-HermesEnv
    $version = (Get-Content (Join-Path $root 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if (-not $version) { $version = '1.0.0' }

    $dockerStatus = if (Test-DockerRunning) { 'Running' } else { 'Stopped' }
    $hermesStatus = if (Test-HermesHealthy) { 'Running' } else { 'Stopped' }

    $telegramStatus = 'Not configured'
    if (Test-TelegramConfigured) {
        $telegramStatus = if (Test-HermesHealthy) { 'Connected' } else { 'Configured' }
    }

    $memoryOk = Test-Path (Join-Path $root 'data\memories')
    $logsOk = Test-Path (Join-Path $root 'data\logs')

    $backupsDir = Join-Path $root 'backups'
    $backupCount = 0
    $lastBackup = 'Never'
    if (Test-Path $backupsDir) {
        $backups = Get-ChildItem $backupsDir -Filter 'backup-*.zip' | Sort-Object LastWriteTime -Descending
        $backupCount = $backups.Count
        if ($backups.Count -gt 0) {
            $lastBackup = $backups[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        }
    }

    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $diskFree = if ($disk) { [math]::Round($disk.FreeSpace / 1GB) } else { 0 }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramFree = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB) } else { 0 }

    $provider = $env['HERMES_PROVIDER_NAME']
    if (-not $provider -and $env['OPENAI_BASE_URL']) {
        $provider = Get-ProviderDisplayName -ProviderUrl $env['OPENAI_BASE_URL']
    }

    return [PSCustomObject]@{
        DockerStatus     = $dockerStatus
        HermesStatus     = $hermesStatus
        TelegramStatus   = $telegramStatus
        MemoryOk         = if ($memoryOk) { 'OK' } else { 'Missing' }
        LogsOk           = if ($logsOk) { 'OK' } else { 'Missing' }
        BackupCount      = $backupCount
        DiskFreeGb       = $diskFree
        RamFreeGb        = $ramFree
        LastBackup       = $lastBackup
        ExternalProvider = $provider
        Version          = $version
    }
}

function Send-TelegramMessage {
    param([string]$Text)   # текст сообщения для владельца сервера

    # П3: отправляет сообщение владельцу через Telegram Bot API.
    # Токен и ID пользователя берём из .env (Get-HermesEnv).
    # Возвращает $true при успехе, $false при любой ошибке —
    # уведомление не должно ронять основной скрипт.
    try {
        $env = Get-HermesEnv                                        # читаем .env как hashtable
        $token = $env['TELEGRAM_BOT_TOKEN']                         # токен бота
        $chatId = ($env['TELEGRAM_ALLOWED_USERS'] -split ',')[0]    # первый разрешённый пользователь = владелец
        if (-not $token -or -not $chatId) { return $false }         # без токена/ID отправлять некуда
        $uri = "https://api.telegram.org/bot$token/sendMessage"     # адрес метода Bot API
        $body = @{ chat_id = $chatId.Trim(); text = $Text }         # параметры запроса
        Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 15 | Out-Null
        return $true
    }
    catch {
        # ошибка сети/токена — просто сообщаем в консоль, не прерываем работу
        Write-Host "Telegram notification failed: $_"
        return $false
    }
}

function New-HermesBackup {
    param([switch]$Quiet)

    # Создаёт backup-YYYY-MM-DD-HHmmss.zip (память, конфиг, логи, sessions/skills/cron)
    $root = Get-HermesProjectRoot                                    # корень проекта
    $timestamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'               # метка времени для имени
    $backupDir = Join-Path $root 'backups'                          # папка архивов
    $zipPath = Join-Path $backupDir "backup-$timestamp.zip"         # путь к новому zip

    # создаём папку backups, если её ещё нет
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    # временный каталог для сборки содержимого
    $tempDir = Join-Path $env:TEMP "hermes-backup-$timestamp"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # вспомогательная: копирует папку data\X -> temp\Y
    $copyDataDir = {
        param([string]$SrcName, [string]$DestName)
        $dest = Join-Path $tempDir $DestName                        # куда класть
        New-Item -ItemType Directory -Path $dest -Force | Out-Null  # создаём папку
        $src = Join-Path $root "data\$SrcName"                      # откуда брать
        if (Test-Path $src) {
            Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # memory / logs
    & $copyDataDir 'memories' 'memory'
    & $copyDataDir 'logs' 'logs'
    # П6: диалоги, навыки, задания cron
    & $copyDataDir 'sessions' 'sessions'
    & $copyDataDir 'skills' 'skills'
    & $copyDataDir 'cron' 'cron'

    # config/ — .env, config.yaml, SOUL.md
    $configDest = Join-Path $tempDir 'config'
    New-Item -ItemType Directory -Path $configDest -Force | Out-Null
    foreach ($file in @(
        @{ Src = Join-Path $root '.env'; Name = '.env' },
        @{ Src = Join-Path $root 'data\config.yaml'; Name = 'config.yaml' },
        @{ Src = Join-Path $root 'data\SOUL.md'; Name = 'SOUL.md' }
    )) {
        if (Test-Path $file.Src) {
            Copy-Item $file.Src (Join-Path $configDest $file.Name) -Force
        }
    }

    # читаем .env для retention / password / mirror
    $envMap = Get-HermesEnv

    # П12: если задан BACKUP_PASSWORD и есть openssl — шифруем .env
    $plainEnv = Join-Path $configDest '.env'
    $encEnv = Join-Path $configDest '.env.enc'
    $backupPassword = $envMap['BACKUP_PASSWORD']
    if ($backupPassword -and (Test-Path $plainEnv)) {
        $openssl = Get-Command openssl -ErrorAction SilentlyContinue
        if ($openssl) {
            # openssl AES-256-CBC + PBKDF2 (как в backup.sh)
            & openssl enc -aes-256-cbc -salt -pbkdf2 -in $plainEnv -out $encEnv -pass "pass:$backupPassword" 2>$null
            if (Test-Path $encEnv) {
                Remove-Item $plainEnv -Force                      # открытый .env в архив не кладём
            }
        }
        else {
            Write-Host 'BACKUP_PASSWORD задан, но openssl не найден — .env останется открытым в архиве.'
        }
    }

    # упаковываем zip
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $zipPath -Force
    Remove-Item $tempDir -Recurse -Force

    # ротация: хранить последние N копий
    $retention = 30
    if ($envMap['BACKUP_RETENTION'] -match '^\d+$') { $retention = [int]$envMap['BACKUP_RETENTION'] }
    $allBackups = Get-ChildItem $backupDir -Filter 'backup-*.zip' | Sort-Object Name -Descending
    if ($allBackups.Count -gt $retention) {
        $allBackups | Select-Object -Skip $retention | Remove-Item -Force
    }

    # Ф4: зеркало архива на другой диск / OneDrive
    $mirror = $envMap['BACKUP_MIRROR_DIR']
    if ($mirror) {
        if (-not (Test-Path $mirror)) {
            New-Item -ItemType Directory -Path $mirror -Force | Out-Null
        }
        Copy-Item $zipPath (Join-Path $mirror (Split-Path $zipPath -Leaf)) -Force
    }

    if (-not $Quiet) { Write-HermesStep -Name 'Backup' -Status 'OK' -Detail $zipPath }
    return $zipPath
}

function Get-HermesBackups {
    # Список доступных архивов
    $root = Get-HermesProjectRoot
    $backupDir = Join-Path $root 'backups'
    if (-not (Test-Path $backupDir)) { return @() }
    return Get-ChildItem $backupDir -Filter 'backup-*.zip' | Sort-Object Name
}

function Restore-HermesBackup {
    param([int]$Index)

    # Восстанавливает выбранный бэкап по номеру (1-based)
    $root = Get-HermesProjectRoot
    $backups = Get-HermesBackups
    if ($Index -lt 1 -or $Index -gt $backups.Count) {
        throw "Invalid backup number: $Index"
    }

    # запоминаем путь ДО safety-бэкапа (иначе номер 1 сдвинется на новый архив)
    $zip = $backups[$Index - 1].FullName

    # П4: страховочный бэкап текущего состояния ДО восстановления
    Write-Host 'Safety backup before restore...'
    try {
        New-HermesBackup -Quiet | Out-Null
    }
    catch {
        Write-Host "Warning: safety backup failed: $_"
    }

    if (-not (Test-Path $zip)) {
        throw "Backup file disappeared: $zip"
    }

    $tempDir = Join-Path $env:TEMP "hermes-restore-$(Get-Random)"
    Expand-Archive -Path $zip -DestinationPath $tempDir -Force

    # остановить контейнер перед восстановлением
    Push-Location $root
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    docker compose stop 2>&1 | Out-Null
    $ErrorActionPreference = $prevEap
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'docker compose stop failed.' }
    Pop-Location

    # вспомогательная: копирует temp\X\* -> data\Y
    $restoreDir = {
        param([string]$SrcName, [string]$DestName)
        $src = Join-Path $tempDir $SrcName
        if (Test-Path $src) {
            $dest = Join-Path $root "data\$DestName"
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            Copy-Item (Join-Path $src '*') $dest -Recurse -Force
        }
    }

    & $restoreDir 'memory' 'memories'
    & $restoreDir 'logs' 'logs'
    # П6: sessions / skills / cron
    & $restoreDir 'sessions' 'sessions'
    & $restoreDir 'skills' 'skills'
    & $restoreDir 'cron' 'cron'

    if (Test-Path (Join-Path $tempDir 'config\config.yaml')) {
        Copy-Item (Join-Path $tempDir 'config\config.yaml') (Join-Path $root 'data\config.yaml') -Force
    }
    if (Test-Path (Join-Path $tempDir 'config\SOUL.md')) {
        Copy-Item (Join-Path $tempDir 'config\SOUL.md') (Join-Path $root 'data\SOUL.md') -Force
    }

    # текущий пароль шифрования (из живого .env, до перезаписи)
    $currentEnv = Get-HermesEnv
    $backupPassword = $currentEnv['BACKUP_PASSWORD']

    # П12: если в архиве .env.enc — расшифровываем openssl
    $encBackup = Join-Path $tempDir 'config\.env.enc'
    $envBackup = Join-Path $tempDir 'config\.env'
    if ((Test-Path $encBackup) -and $backupPassword) {
        $openssl = Get-Command openssl -ErrorAction SilentlyContinue
        if ($openssl) {
            & openssl enc -d -aes-256-cbc -pbkdf2 -in $encBackup -out $envBackup -pass "pass:$backupPassword" 2>$null
        }
        else {
            Write-Host 'Skip .env.enc: openssl не найден, секретный .env не восстановлен.'
        }
    }

    # восстанавливаем .env только если он полный (есть бот-токен)
    if (Test-Path $envBackup) {
        $envText = Get-Content $envBackup -Raw
        if ($envText -match '(?m)^TELEGRAM_BOT_TOKEN=.+') {
            Copy-Item $envBackup (Join-Path $root '.env') -Force
        }
        else {
            Write-Host 'Skip .env restore: backup has no secrets (keeping current .env).'
        }
    }

    Remove-Item $tempDir -Recurse -Force
    Ensure-Hermes -Quiet
}

function Ensure-TelegramBackupCommands {
    param([switch]$Quiet)

    # Telegram /bkp and /backup -> exec script (no LLM, no /cron)
    $root = Get-HermesProjectRoot
    $src = Join-Path $root 'scripts\backup.sh'
    $dstDir = Join-Path $root 'data\scripts'
    $configPath = Join-Path $root 'data\config.yaml'

    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    foreach ($name in @('backup.sh', 'list-backups.sh', 'restore.sh', 'health.sh', 'send-backup.sh')) {
        $srcFile = Join-Path $root "scripts\$name"
        if (Test-Path $srcFile) {
            Copy-Item $srcFile (Join-Path $dstDir $name) -Force
        }
    }

    if (-not (Test-Path $configPath)) { return $false }

    $content = Get-Content $configPath -Raw
    if ($content -notmatch '(?m)^quick_commands:') {
        $block = @"

quick_commands:
  bkp:
    type: exec
    command: sh /opt/scripts/backup.sh
  backup:
    type: exec
    command: sh /opt/scripts/backup.sh
  backups:
    type: exec
    command: sh /opt/scripts/list-backups.sh
  restore1:
    type: exec
    command: sh /opt/scripts/restore.sh 1
  restore2:
    type: exec
    command: sh /opt/scripts/restore.sh 2
  restore3:
    type: exec
    command: sh /opt/scripts/restore.sh 3
  health:
    type: exec
    command: sh /opt/scripts/health.sh
  sendbackup:
    type: exec
    command: sh /opt/scripts/send-backup.sh
"@
        # дописываем блок; UTF-8 без BOM через чтение+Write-HermesTextFile
        $newLines = @(Get-Content $configPath) + ($block -split "`r?`n")
        Write-HermesTextFile -Path $configPath -Lines $newLines
    }
    elseif ($content -notmatch 'restore1:') {
        $block = @"
  backups:
    type: exec
    command: sh /opt/scripts/list-backups.sh
  restore1:
    type: exec
    command: sh /opt/scripts/restore.sh 1
  restore2:
    type: exec
    command: sh /opt/scripts/restore.sh 2
  restore3:
    type: exec
    command: sh /opt/scripts/restore.sh 3
  health:
    type: exec
    command: sh /opt/scripts/health.sh
  sendbackup:
    type: exec
    command: sh /opt/scripts/send-backup.sh
"@
        $newLines = @(Get-Content $configPath) + ($block -split "`r?`n")
        Write-HermesTextFile -Path $configPath -Lines $newLines
    }
    else {
        # Ф1/Ф3: дописываем health/sendbackup, если их ещё нет в живом конфиге
        $extra = @()
        if ($content -notmatch '(?m)^\s*health:') {
            $extra += '  health:'
            $extra += '    type: exec'
            $extra += '    command: sh /opt/scripts/health.sh'
        }
        if ($content -notmatch '(?m)^\s*sendbackup:') {
            $extra += '  sendbackup:'
            $extra += '    type: exec'
            $extra += '    command: sh /opt/scripts/send-backup.sh'
        }
        if ($extra.Count -gt 0) {
            $newLines = @(Get-Content $configPath) + $extra
            Write-HermesTextFile -Path $configPath -Lines $newLines
        }
    }

    if (-not $Quiet) {
        Write-HermesStep -Name 'Telegram backup' -Status 'OK' -Detail '/bkp /health /sendbackup'
    }

    return $true
}

function Ensure-BackupSchedule {
    param([switch]$Quiet)

    # Регистрирует ежедневную задачу Windows Task Scheduler на 03:00
    $root = Get-HermesProjectRoot
    $taskName = 'HermesHomeServer-NightlyBackup'
    $scriptPath = Join-Path $root 'backup.ps1'

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Quiet"
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:00'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Hermes Home Server nightly backup' | Out-Null

    if (-not $Quiet) { Write-HermesStep -Name 'Backup' -Status 'OK' -Detail 'schedule 03:00' }
}

function Remove-BackupSchedule {
    $taskName = 'HermesHomeServer-NightlyBackup'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Ensure-WatchdogSchedule {
    param([switch]$Quiet)

    # П8: задача Windows «каждые 15 минут» — watchdog.ps1
    $root = Get-HermesProjectRoot
    $taskName = 'HermesHomeServer-Watchdog'
    $scriptPath = Join-Path $root 'watchdog.ps1'

    # действие: powershell -File watchdog.ps1
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    # триггер: каждые 15 минут (RepetitionDuration ~10 лет — MaxValue на части Windows ломается)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # пересоздаём задачу, если уже была
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Hermes Home Server watchdog (15 min)' | Out-Null

    if (-not $Quiet) { Write-HermesStep -Name 'Watchdog' -Status 'OK' -Detail 'every 15 min' }
}

function Remove-WatchdogSchedule {
    # снимаем задачу watchdog при uninstall
    $taskName = 'HermesHomeServer-Watchdog'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Update-Hermes {
    param([switch]$Quiet)

    # Backup → pull → restart → health check
    if (-not $Quiet) { Write-Host 'Backup...' }
    New-HermesBackup -Quiet | Out-Null

    $root = Get-HermesProjectRoot
    Push-Location $root
    try {
        if (-not $Quiet) { Write-Host 'Pull latest image...' }
        docker compose pull
        if (-not $Quiet) { Write-Host 'Restart...' }
        docker compose up -d
    }
    finally {
        Pop-Location
    }

    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        if (Test-HermesHealthy) { break }
        Start-Sleep -Seconds 5
    }

    if (-not (Test-HermesHealthy)) {
        throw 'Health check failed after update.'
    }

    if (-not $Quiet) { Write-Host 'Done.' }
}

function Ensure-ServerPower {
    param([switch]$Quiet)

    # Keep Hermes running when laptop lid is closed (requires admin for lid setting)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    # Never sleep on AC power
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change monitor-timeout-ac 10 | Out-Null

    # On battery: allow sleep after 30 min (saves battery if unplugged)
    powercfg /change standby-timeout-dc 30 | Out-Null
    powercfg /change monitor-timeout-dc 5 | Out-Null

    # Disable hybrid sleep on AC
    powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_SLEEP HYBRIDSLEEP 0 2>$null | Out-Null
    powercfg /SETACTIVE SCHEME_CURRENT 2>$null | Out-Null

    $lidOk = $false
    if ($isAdmin) {
        $subButtons = '4f971e89-eebd-4455-a8de-9e59040e7347'
        $lidClose   = '5ca83367-6e45-459f-a27d-476b1d01e936'
        # 0 = Do nothing when lid closes
        powercfg /SETACVALUEINDEX SCHEME_CURRENT $subButtons $lidClose 0 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subButtons $lidClose 0 2>$null | Out-Null
            powercfg /SETACTIVE SCHEME_CURRENT 2>$null | Out-Null
            $lidOk = ($LASTEXITCODE -eq 0)
        }
    }

    if (-not $Quiet) {
        Write-HermesStep -Name 'Power (AC sleep)' -Status 'OK' -Detail 'disabled'
        if ($lidOk) {
            Write-HermesStep -Name 'Power (lid close)' -Status 'OK' -Detail 'do nothing'
        }
        elseif (-not $isAdmin) {
            Write-HermesStep -Name 'Power (lid close)' -Status 'SKIP' -Detail 'run configure-power.ps1 as Admin'
        }
        else {
            Write-HermesStep -Name 'Power (lid close)' -Status 'SKIP' -Detail 'set manually in Windows Settings'
        }
    }

    return [PSCustomObject]@{
        SleepDisabledOnAc = $true
        LidCloseOk        = $lidOk
        NeedsAdmin        = -not $isAdmin
    }
}

function Uninstall-HermesHome {
    param([switch]$KeepData)

    $root = Get-HermesProjectRoot
    Remove-BackupSchedule
    Remove-WatchdogSchedule

    Push-Location $root
    docker compose down -v 2>&1 | Out-Null
    Pop-Location

    if (-not $KeepData) {
        Remove-Item (Join-Path $root 'data') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $root 'backups') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $root '.env') -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function (Get-Command -Module $ExecutionContext.SessionState.Module | Select-Object -ExpandProperty Name)
