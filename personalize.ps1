#Requires -Version 5.1
# Ф6: мастер персонализации — заполняет data\SOUL.md

$ErrorActionPreference = 'Stop'
# подключаем модуль (нужен Write-HermesTextFile)
Import-Module (Join-Path $PSScriptRoot 'modules\HermesHomeServer.psm1') -Force

Write-Host ''
Write-Host 'Hermes - персонализация (SOUL.md)'
Write-Host 'Ответьте коротко на 4 вопроса. Пустой ввод = значение по умолчанию.'
Write-Host ''

# спрашиваем имя ассистента
$name = Read-Host 'Как зовут ассистента'
if (-not $name) { $name = 'Hermes' }

# тон общения
$tone = Read-Host 'Тон общения (например: дружелюбный, деловой, короткий)'
if (-not $tone) { $tone = 'дружелюбный и по делу' }

# язык ответов
$lang = Read-Host 'На каком языке отвечать по умолчанию'
if (-not $lang) { $lang = 'русский' }

# что важно помнить о владельце
$about = Read-Host 'Что важно знать о вас (хобби, работа, предпочтения)'
if (-not $about) { $about = 'владелец домашнего сервера Hermes' }

# собираем простой SOUL.md
$lines = @(
    "# $name"
    ''
    '## Кто я'
    "Меня зовут $name. Я домашний ассистент владельца сервера Hermes."
    ''
    '## Как я говорю'
    "- Тон: $tone"
    "- Язык по умолчанию: $lang"
    ''
    '## О владельце'
    $about
    ''
    '## Правила'
    '- Отвечаю кратко, если не просят подробностей.'
    '- Не выдумываю факты о файлах и сервере - сначала проверяю.'
    '- Секреты (.env, токены) не цитирую в чат.'
)

# путь к SOUL.md
$soulPath = Join-Path $PSScriptRoot 'data\SOUL.md'
# папка data должна существовать
$dataDir = Join-Path $PSScriptRoot 'data'
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

# пишем UTF-8 без BOM
Write-HermesTextFile -Path $soulPath -Lines $lines

Write-Host ''
Write-Host "Готово: $soulPath"
Write-Host 'Перезапуск не обязателен - Hermes подхватит SOUL.md при следующем ответе.'
Write-Host ''
