#Requires -Version 5.1
# Hermes Home Server — проверка, что модели из fallback-цепочки ещё доступны и бесплатны

# останавливаем скрипт при любой ошибке
$ErrorActionPreference = 'Stop'

# список моделей, которые должны быть доступны (цепочка из data\config.yaml)
$models = @(
    'nvidia/nemotron-3-super-120b-a12b:free',
    'openai/gpt-oss-20b:free',
    'google/gemma-4-31b-it:free'
)

# путь к лог-файлу (рядом со скриптом, в data\logs)
$logDir = Join-Path $PSScriptRoot 'data\logs'
$logFile = Join-Path $logDir 'model-check.log'

# создаём папку логов, если её нет
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# текущая дата-время для записей в лог
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

try {
    # запрашиваем у OpenRouter полный список моделей (без ключа)
    $response = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/models'
}
catch {
    # если сам запрос не удался — пишем это в лог и выходим
    Add-Content -Path $logFile -Value "$now ERROR: API request failed: $_"
    exit 1
}

# собираем в хэш только бесплатные модели (цена запроса и ответа = 0)
$freeIds = @{}
foreach ($m in $response.data) {
    if ($m.pricing.prompt -eq '0' -and $m.pricing.completion -eq '0') {
        $freeIds[$m.id] = $true
    }
}

# проверяем каждую модель из нашей цепочки
$problems = 0
foreach ($model in $models) {
    if ($freeIds.ContainsKey($model)) {
        # модель на месте и бесплатна — пишем OK
        Add-Content -Path $logFile -Value "$now OK: $model"
    }
    else {
        # модель исчезла или стала платной — пишем предупреждение
        Add-Content -Path $logFile -Value "$now WARNING: $model is no longer available/free! Update data\config.yaml"
        $problems++
    }
}

# итоговая строка: сколько проблем найдено
Add-Content -Path $logFile -Value "$now Done: $($models.Count) checked, $problems problem(s)."
