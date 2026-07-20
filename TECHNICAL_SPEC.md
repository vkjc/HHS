# Hermes Home Server — техническая спецификация (актуальное состояние)

## Цель

Одной командой развернуть домашний сервер Hermes Agent на Windows 11 с Telegram-шлюзом, ночными бэкапами и автовосстановлением контейнера.

```powershell
.\install.ps1
```

- Установка идемпотентная: повторный запуск с уже настроенным окружением печатает статусы и `Nothing to do.`
- Без ручной правки `docker-compose.yml` и без локальных LLM.

---

## Требования

| Параметр | Значение |
|----------|----------|
| ОС | Windows 11 |
| Сеть | Домашняя Wi‑Fi, без публикации в интернет |
| Runtime | Docker Desktop |
| Коммуникации | Только Telegram |
| LLM | Любой OpenAI-compatible (OpenRouter, Kimi, DeepSeek, Gemini, Groq, OpenAI, Claude и т.п.) |

**Локально хранится:** память Hermes, конфиги, логи, архивы бэкапов. Локальных моделей нет.

---

## Архитектура

```
Windows 11
    │
Docker Desktop  (container: hermes-home)
    │
┌───────────────────────────────────────┐
│  Hermes Gateway + Telegram            │
│  volumes: ./data, ./backups, ./scripts│
│  healthcheck: pgrep gateway           │
│  limits: 4G RAM / 2 CPU               │
└───────────────────────────────────────┘
    │
data/  memories, config, sessions, skills, cron, logs, SOUL.md
backups/  backup-YYYY-MM-DD-HHmmss.zip
Task Scheduler: NightlyBackup 03:00 | Watchdog 15 min | ModelCheck Sun 04:00
```

Образ: `nousresearch/hermes-agent:latest` (gateway mode, `HERMES_HOME=/opt/data`).

Документация upstream: https://hermes-agent.nousresearch.com/docs/user-guide/docker

---

## Структура каталогов

```
hhs/   (корень проекта)
├── docker-compose.yml          # hermes-home, volumes, healthcheck, limits
├── .env / .env.template        # секреты и настройки (не в git)
├── VERSION
├── TECHNICAL_SPEC.md
├── modules/
│   ├── HermesHomeServer.psm1   # вся логика PowerShell
│   └── HermesHomeServer.psd1   # манифест экспорта
├── scripts/                    # монтируются в контейнер :ro → /opt/scripts
│   ├── backup.sh
│   ├── restore.sh
│   ├── list-backups.sh
│   ├── health.sh
│   └── send-backup.sh
├── data/                       # → /opt/data (persistent)
│   ├── memories/
│   ├── sessions/
│   ├── skills/
│   ├── cron/
│   ├── logs/
│   ├── config.yaml
│   ├── SOUL.md
│   ├── state.db*               # если есть у агента
│   └── auth.json               # если есть у агента
├── backups/                    # → /opt/backups
│   └── backup-YYYY-MM-DD-HHmmss.zip
├── tests/
│   ├── Run-Tests.ps1
│   ├── HermesHomeServer.Tests.ps1
│   ├── Scripts.Smoke.Tests.ps1
│   ├── Backup.Integration.Tests.ps1
│   └── Backup.Destructive.Tests.ps1
├── install.ps1
├── update.ps1
├── status.ps1
├── backup.ps1
├── restore.ps1
├── uninstall.ps1
├── personalize.ps1
├── watchdog.ps1
├── check-models.ps1
├── configure-power.ps1
├── setup-telegram-backup.ps1
└── test-backup-restore.ps1
```

---

## Команды (хост)

| Скрипт | Назначение |
|--------|------------|
| `.\install.ps1` | Идемпотентная установка: Docker, контейнер, `.env`, расписания, quick_commands |
| `.\update.ps1` | Бэкап → `docker compose pull` → restart → health |
| `.\status.ps1` | Docker / Hermes / Telegram / память / логи / бэкапы / диск / RAM |
| `.\backup.ps1` | Ручной бэкап (`New-HermesBackup`) |
| `.\restore.ps1` | Выбор архива (1 = самый новый); расшифровка `.env.enc` при необходимости |
| `.\uninstall.ps1` | Снять задачи, `compose down`; опционально удалить data/backups/.env |
| `.\personalize.ps1` | Мастер `data\SOUL.md` |
| `.\watchdog.ps1` | Проверка healthy + disk alert (вызывается планировщиком) |
| `.\check-models.ps1` | Проверка `:free` моделей OpenRouter + авто-замена |
| `.\configure-power.ps1` | Питание: не спать на AC / крышка (нужен Admin) |
| `.\setup-telegram-backup.ps1` | Дописать Telegram quick_commands в `config.yaml` |
| `.\tests\Run-Tests.ps1` | Pester (unit + smoke + integration); `-SkipIntegration` быстрее |

---

## Telegram quick commands

Команды без LLM (`type: exec` → скрипты в `/opt/scripts`):

| Команда | Действие |
|---------|----------|
| `/bkp` / `/backup` | Создать архив (`backup.sh`) |
| `/backups` | Список архивов, 1 = newest |
| `/restore1` … `/restore3` | Восстановить N-й архив (**без** `.env`) |
| `/health` | Статус gateway |
| `/sendbackup` | Отправить последний zip в чат (лимит Telegram ~50 MB) |

---

## Бэкапы

### Что входит в zip

- `memory/` ← `data/memories`
- `logs/`
- `sessions/`, `skills/`, `cron/`
- `config/config.yaml`, `config/SOUL.md`
- `config/state.db*` и `config/auth.json` — если файлы есть
- `config/.env` **или** `config/.env.enc` (если задан `BACKUP_PASSWORD` и есть `openssl`)

### Поведение

| Функция | Детали |
|---------|--------|
| Расписание | Ежедневно 03:00 (`HermesHomeServer-NightlyBackup`) |
| Retention | `BACKUP_RETENTION` (по умолчанию 30) |
| Порядок | Newest-first (как `ls -1t`); **Index 1 = самый новый** |
| Safety backup | Перед restore (host и container) создаётся страховочный архив |
| Зеркало | `BACKUP_MIRROR_DIR`: на хосте всегда копирует; в контейнере — только если путь существует внутри контейнера |
| Шифрование | `openssl` AES-256-CBC + PBKDF2; пароль через `-pass file:` (временный файл), не в cmdline |

### Важно про секреты

- **Telegram / `restore.sh`:** данные и конфиг восстанавливаются; **`.env` / секреты этим путём НЕ трогаются**. Нужен `.\restore.ps1` на хосте (расшифровывает `.env.enc` при `BACKUP_PASSWORD`).
- Контейнер читает секреты только из корневого `.env` хоста (`env_file`).

---

## Надёжность и эксплуатация

| Компонент | Поведение |
|-----------|-----------|
| Healthcheck | `pgrep -f 'hermes gateway'`; `Test-HermesHealthy` = true только при `healthy` (если Health нет — fallback на Running) |
| Watchdog | Каждые 15 мин; при unhealthy — `compose up -d` + Telegram |
| Disk alert | < 10 ГБ на диске проекта; debounce 6 часов (`data/logs/disk-alert.last`) |
| Model fallbacks | Для OpenRouter в `config.yaml` — цепочка `:free` моделей |
| ModelCheck | Еженедельно вс 04:00; исчезнувшие `:free` авто-заменяются |
| Power | `Ensure-ServerPower` / `configure-power.ps1` — не усыплять ноутбук на AC |
| Тесты | Pester; покрытие модуля ~35%; destructive restore — отдельно |

`install.ps1` считает «Nothing to do», только если настроены Docker, Hermes (healthy), Telegram, NightlyBackup, **Watchdog** и **ModelCheck**. Иначе досоздаёт недостающее.

---

## Переменные `.env` (шаблон)

| Ключ | Назначение |
|------|------------|
| `TELEGRAM_BOT_TOKEN` | Токен бота |
| `TELEGRAM_ALLOWED_USERS` | ID пользователя(ей) |
| `OPENAI_BASE_URL` / `OPENAI_API_KEY` | Провайдер |
| `HERMES_MODEL` / `HERMES_PROVIDER_NAME` | Модель и имя для status |
| `BACKUP_RETENTION` | Сколько zip хранить |
| `BACKUP_PASSWORD` | Шифрование `.env` в архиве (опционально) |
| `BACKUP_MIRROR_DIR` | Копия zip на другой диск / OneDrive (опционально) |

---

## Ограничения

1. **Один инстанс на бот-токен** — два контейнера с одним токеном конфликтуют в Telegram.
2. **Telegram restore не восстанавливает `.env`** — только `restore.ps1` на хосте расшифровывает `.env.enc` и пишет корневой `.env`.
3. **Free-tier лимиты** провайдеров (OpenRouter `:free` и др.) — возможны 429/даунтайм; помогают fallbacks и `check-models.ps1`.
4. **`/sendbackup`** ограничен размером файла Telegram (~50 MB); большие архивы — через `BACKUP_MIRROR_DIR` или копирование `backups\`.
5. **Зеркало из контейнера** работает только для путей, видимых внутри контейнера; Windows-путь зеркалится через `New-HermesBackup` на хосте.

---

## Слои реализации

1. `docker-compose.yml` — контейнер, volumes, healthcheck, mem/cpu limits  
2. `.env.template` / `.env` — секреты и опции бэкапа  
3. `modules/HermesHomeServer.psm1` — Docker, env, backup/restore, расписания, status  
4. `scripts/*.sh` — Telegram exec и backup внутри контейнера (LF endings)  
5. Корневые `*.ps1` — оркестраторы для пользователя  
6. `tests/` — Pester unit / smoke / integration  

---

## Быстрый старт после установки

```powershell
.\status.ps1
.\personalize.ps1          # опционально SOUL.md
# в Telegram боту: hello, /health, /bkp
.\tests\Run-Tests.ps1 -SkipIntegration
```
