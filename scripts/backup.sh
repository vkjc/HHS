#!/bin/sh
# Safe backup for live Hermes data -> /opt/backups/backup-YYYY-MM-DD-HHmmss.zip

# метка времени для имени архива
TS=$(date +%Y-%m-%d-%H%M%S)
# каталог с готовыми архивами (смонтирован с хоста)
BACKUP_DIR="/opt/backups"
# полный путь к новому zip
ARCHIVE="$BACKUP_DIR/backup-$TS.zip"
# временная папка для сборки содержимого архива
TMP=$(mktemp -d)

# П5: сколько архивов хранить (из .env контейнера, иначе 30)
RETENTION=${BACKUP_RETENTION:-30}

# копирует все файлы из src в dst, сохраняя относительные пути
copy_files() {
  # исходная папка
  src="$1"
  # папка назначения
  dst="$2"
  # если источника нет — ничего не делаем
  [ -d "$src" ] || return 0
  # создаём назначение
  mkdir -p "$dst"
  # обходим все файлы в источнике
  find "$src" -type f 2>/dev/null | while IFS= read -r file; do
    # относительный путь внутри src
    rel="${file#$src/}"
    # куда копировать
    target="$dst/$rel"
    # создаём родительские каталоги
    mkdir -p "$(dirname "$target")"
    # копируем файл (ошибки игнорируем)
    cp -f "$file" "$target" 2>/dev/null || true
  done
}

# создаём каркас временного дерева архива
mkdir -p "$TMP/memory" "$TMP/config" "$TMP/logs" "$TMP/sessions" "$TMP/skills" "$TMP/cron"

# память агента
copy_files /opt/data/memories "$TMP/memory"
# логи
copy_files /opt/data/logs "$TMP/logs"
# П6: диалоги, навыки и задания cron
copy_files /opt/data/sessions "$TMP/sessions"
copy_files /opt/data/skills "$TMP/skills"
copy_files /opt/data/cron "$TMP/cron"

# копируем конфиги из /opt/data в архив (config.yaml и SOUL.md)
for f in config.yaml SOUL.md; do
  # если файл есть — кладём в config/
  if [ -f "/opt/data/$f" ]; then
    cp -f "/opt/data/$f" "$TMP/config/" 2>/dev/null || true
  fi
done

# ФИКС: секреты не лежат в /opt/data/.env —
# они приходят как переменные окружения из корневого .env (env_file).
# Собираем полный .env для архива из окружения контейнера.
ENV_OUT="$TMP/config/.env"
# создаём пустой файл
: > "$ENV_OUT"
# ключи, которые нужно сохранить в бэкап
for key in TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS OPENAI_BASE_URL OPENAI_API_KEY \
           HERMES_MODEL HERMES_PROVIDER_NAME BACKUP_RETENTION BACKUP_PASSWORD BACKUP_MIRROR_DIR \
           TELEGRAM_HOME_CHANNEL TELEGRAM_HOME_CHANNEL_THREAD_ID; do
  # читаем значение переменной по имени
  val=$(printenv "$key")
  # пишем KEY=value (даже если пусто)
  echo "$key=$val" >> "$ENV_OUT"
done

# П12: если задан BACKUP_PASSWORD — шифруем .env перед упаковкой
if [ -n "$BACKUP_PASSWORD" ] && [ -f "$ENV_OUT" ]; then
  # шифруем openssl AES-256-CBC, результат — .env.enc
  openssl enc -aes-256-cbc -salt -pbkdf2 -in "$ENV_OUT" -out "$TMP/config/.env.enc" -pass "pass:$BACKUP_PASSWORD" 2>/dev/null
  # если шифрование удалось — убираем открытый .env из архива
  if [ -f "$TMP/config/.env.enc" ]; then
    rm -f "$ENV_OUT"
  fi
fi

# каталог бэкапов на хосте должен существовать
mkdir -p "$BACKUP_DIR"

# упаковываем временное дерево в zip через python (в образе нет zip)
python3 <<PY
import os
import zipfile
from pathlib import Path

# временный каталог со сборкой
tmp = Path("$TMP")
# путь к итоговому архиву
archive = Path("$ARCHIVE")

# создаём zip со сжатием
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
    # обходим все папки, которые кладём в архив
    for folder in ("memory", "config", "logs", "sessions", "skills", "cron"):
        base = tmp / folder
        # папки может не быть — пропускаем
        if not base.exists():
            continue
        # все файлы внутри папки
        for path in base.rglob("*"):
            if path.is_file():
                # путь внутри zip — относительный от tmp
                zf.write(path, path.relative_to(tmp).as_posix())

# печатаем результат для Telegram/логов
print(f"Backup created: {archive}")
print(archive.name)
PY

# код выхода python
status=$?
# чистим временную папку
rm -rf "$TMP"

# если упаковка упала — выходим с ошибкой
if [ "$status" -ne 0 ]; then
  echo "Backup failed" >&2
  exit 1
fi

# П5: ротация — оставляем только последние RETENTION архивов
count=0
for old in $(ls -1t "$BACKUP_DIR"/backup-*.zip 2>/dev/null); do
  count=$((count + 1))
  # всё, что старше лимита — удаляем
  if [ "$count" -gt "$RETENTION" ]; then
    rm -f "$old"
  fi
done
