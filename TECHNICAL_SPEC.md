# Hermes Home Server v1.0 — Техническое задание

## Цель

Одной командой развернуть домашний сервер Hermes на Windows.

```powershell
.\install.ps1
```

- Время установки: **< 10 минут**
- Без ручной настройки Docker
- Без ручного редактирования YAML

---

## Требования

### ОС

Windows 11

### Использование

- Домашняя WiFi сеть
- Без публикации в Интернет

### Локально хранится только

- Hermes Memory
- Configs
- Logs
- Backups

Никаких локальных LLM.

### Провайдеры

Любые OpenAI-compatible: OpenRouter, Kimi, DeepSeek, Gemini, Groq, OpenAI, Claude.

### Коммуникации

Только Telegram.

### Backup

- Автоматически, каждые сутки (03:00)
- Хранить последние N копий (по умолчанию 30)

---

## Архитектура

```
Windows
    │
Docker Desktop
    │
──────────────────────────
Hermes + Telegram Gateway
──────────────────────────
    │
Memory / Config / Logs
    │
Nightly Backup
```

---

## Команды

| Скрипт | Назначение |
|--------|------------|
| `install.ps1` | Установка (идемпотентная) |
| `update.ps1` | Backup → pull → restart → health check |
| `status.ps1` | Статус всех компонентов |
| `backup.ps1` | Ручной бэкап |
| `restore.ps1` | Восстановление из списка |
| `uninstall.ps1` | Удаление |

---

## install.ps1

Идемпотентный. При повторном запуске:

```
Docker...............OK
Hermes...............OK
Telegram.............OK
Backup...............OK

Nothing to do.
```

Спрашивает только:

1. Telegram Bot Token
2. Telegram User ID
3. LLM Provider URL
4. API Key

---

## Структура проекта

```
hermes-home-server/
├── docker-compose.yml      # Hermes + volume ./data:/opt/data
├── .env.template           # Шаблон переменных
├── modules/
│   └── HermesHomeServer.psm1
├── install.ps1             # Оркестратор
├── status.ps1
├── backup.ps1
├── restore.ps1
├── update.ps1
├── uninstall.ps1
├── data/                   # Persistent Hermes state
└── backups/                # backup-YYYY-MM-DD-HHmmss.zip
```

---

## Слои реализации

1. **docker-compose.yml** — конфигурация Hermes с persistent storage
2. **.env.template** — переменные Telegram, LLM, backup
3. **PowerShell-модули** — `Ensure-Docker`, `Ensure-Hermes`, `Ensure-Backup` и др.
4. **install.ps1** — оркестратор
5. **Тестирование** — чистая Windows 11, одна команда

---

## Образ Docker

`nousresearch/hermes-agent:latest` — gateway mode, volume `/opt/data`.

Документация: https://hermes-agent.nousresearch.com/docs/user-guide/docker
