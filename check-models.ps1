#Requires -Version 5.1
# Hermes Home Server — проверка :free моделей + Ф7 авто-замена исчезнувших

# останавливаем скрипт при любой ошибке
$ErrorActionPreference = 'Stop'

# подключаем общий модуль
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

# путь к конфигу
$configPath = Join-Path $PSScriptRoot 'data\config.yaml'
# путь к лог-файлу
$logDir = Join-Path $PSScriptRoot 'data\logs'
$logFile = Join-Path $logDir 'model-check.log'

# создаём папку логов, если её нет
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# текущая дата-время для записей в лог
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# читаем список моделей из config.yaml (default + блок models:)
function Get-ConfigModels {
    param([string]$Path)
    $models = @()
    if (-not (Test-Path $Path)) { return $models }
    $lines = Get-Content $Path
    $inModels = $false
    foreach ($line in $lines) {
        # строка model.default:
        if ($line -match '^\s*default:\s*(.+)\s*$') {
            $models += $Matches[1].Trim()
        }
        # начало списка models: внутри custom_providers
        if ($line -match '^\s*models:\s*$') {
            $inModels = $true
            continue
        }
        if ($inModels) {
            # элемент списка "- id"
            if ($line -match '^\s*-\s+(\S+)\s*$') {
                $models += $Matches[1].Trim()
                continue
            }
            # вышли из списка
            if ($line -match '^\S' -or ($line -match '^\s+\w+:' -and $line -notmatch '^\s*-')) {
                $inModels = $false
            }
        }
    }
    # уникальные, сохраняем порядок
    $seen = @{}
    $out = @()
    foreach ($m in $models) {
        if (-not $seen.ContainsKey($m)) {
            $seen[$m] = $true
            $out += $m
        }
    }
    return $out
}

# запасной список, если config пуст
$models = Get-ConfigModels -Path $configPath
if ($models.Count -eq 0) {
    $models = @(
        'nvidia/nemotron-3-super-120b-a12b:free',
        'openai/gpt-oss-20b:free',
        'google/gemma-4-31b-it:free'
    )
}

try {
    # запрашиваем у OpenRouter полный список моделей
    $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/models' -TimeoutSec 60
}
catch {
    # П3: падение API — в лог и в Telegram
    Add-Content -Path $logFile -Value "$now ERROR: API request failed: $_"
    Send-TelegramMessage -Text "Hermes: check-models не смог запросить OpenRouter: $_" | Out-Null
    exit 1
}

# хэш бесплатных моделей id -> объект
$freeMap = @{}
foreach ($m in $response.data) {
    if ($m.pricing.prompt -eq '0' -and $m.pricing.completion -eq '0') {
        $freeMap[$m.id] = $m
    }
}

# проблемные модели и карта замен old -> new
$badModels = @()
$replacements = @{}

foreach ($model in $models) {
    if ($freeMap.ContainsKey($model)) {
        Add-Content -Path $logFile -Value "$now OK: $model"
    }
    else {
        Add-Content -Path $logFile -Value "$now WARNING: $model is no longer available/free"
        $badModels += $model

        # Ф7: ищем замену среди :free, которой ещё нет в цепочке
        $used = @{}
        foreach ($x in $models) { $used[$x] = $true }
        foreach ($x in $replacements.Values) { $used[$x] = $true }

        $candidate = $null
        foreach ($id in ($freeMap.Keys | Sort-Object)) {
            if ($id -notmatch ':free$') { continue }
            if ($used.ContainsKey($id)) { continue }
            $candidate = $id
            break
        }
        if ($candidate) {
            $replacements[$model] = $candidate
            Add-Content -Path $logFile -Value "$now REPLACE: $model -> $candidate"
        }
    }
}

# применяем замены в config.yaml
if ($replacements.Count -gt 0 -and (Test-Path $configPath)) {
    $text = Get-Content $configPath -Raw
    foreach ($old in $replacements.Keys) {
        $new = $replacements[$old]
        $text = $text -replace [regex]::Escape($old), $new
    }
    # пишем без BOM
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $text, $utf8)

    # перезапускаем контейнер, чтобы подхватил конфиг
    try {
        Push-Location $PSScriptRoot
        docker compose restart 2>&1 | Out-Null
    }
    finally {
        Pop-Location
    }

    $pairs = ($replacements.GetEnumerator() | ForEach-Object { "$($_.Key) -> $($_.Value)" }) -join '; '
    $msg = "Hermes: авто-замена моделей: $pairs. Контейнер перезапущен."
    Send-TelegramMessage -Text $msg | Out-Null
    Add-Content -Path $logFile -Value "$now Done: auto-replaced $($replacements.Count) model(s)."
}
elseif ($badModels.Count -gt 0) {
    $msg = "Hermes: модели больше не доступны/бесплатны: $($badModels -join ', '). Обновите data\config.yaml."
    Send-TelegramMessage -Text $msg | Out-Null
    Add-Content -Path $logFile -Value "$now Done: $($models.Count) checked, $($badModels.Count) problem(s), no replacement."
}
else {
    Add-Content -Path $logFile -Value "$now Done: $($models.Count) checked, 0 problem(s)."
}
