#!/bin/sh
# Restore backup by number (1=newest). Usage: restore.sh [N]

# номер бэкапа (1 = самый новый)
NUM=${1:-1}
# каталог архивов
BACKUP_DIR="/opt/backups"
# временная папка для распаковки
TMP=$(mktemp -d)

# выбирает N-й архив по времени (новые сверху)
pick_file() {
  n=0
  for f in $(ls -1t "$BACKUP_DIR"/backup-*.zip 2>/dev/null); do
    n=$((n + 1))
    if [ "$n" -eq "$NUM" ]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# сначала запоминаем нужный zip (до safety-бэкапа — иначе номер «1» сдвинется)
ZIP=$(pick_file)
# проверяем, что файл существует
if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
  echo "Invalid backup number: $NUM" >&2
  rm -rf "$TMP"
  exit 1
fi

# П4: страховочный бэкап текущего состояния ПЕРЕД восстановлением
# (новый архив станет самым свежим, но ZIP уже выбран выше)
echo "Safety backup before restore..."
sh /opt/scripts/backup.sh || echo "Warning: safety backup failed, continuing restore..."

# распаковываем выбранный ранее архив
python3 <<PY
import zipfile
from pathlib import Path

zipfile.ZipFile("$ZIP").extractall("$TMP")
print("Extracted:", "$ZIP")
PY

# память агента
if [ -d "$TMP/memory" ]; then
  mkdir -p /opt/data/memories
  cp -a "$TMP/memory/." /opt/data/memories/ 2>/dev/null || true
fi
# логи
if [ -d "$TMP/logs" ]; then
  mkdir -p /opt/data/logs
  cp -a "$TMP/logs/." /opt/data/logs/ 2>/dev/null || true
fi
# П6: sessions / skills / cron
if [ -d "$TMP/sessions" ]; then
  mkdir -p /opt/data/sessions
  cp -a "$TMP/sessions/." /opt/data/sessions/ 2>/dev/null || true
fi
if [ -d "$TMP/skills" ]; then
  mkdir -p /opt/data/skills
  cp -a "$TMP/skills/." /opt/data/skills/ 2>/dev/null || true
fi
if [ -d "$TMP/cron" ]; then
  mkdir -p /opt/data/cron
  cp -a "$TMP/cron/." /opt/data/cron/ 2>/dev/null || true
fi
# LLM Wiki (Карпаты) — всегда восстанавливаем, если есть в архиве
if [ -d "$TMP/wiki" ]; then
  mkdir -p /opt/data/wiki
  cp -a "$TMP/wiki/." /opt/data/wiki/ 2>/dev/null || true
fi
# основной конфиг Hermes
if [ -f "$TMP/config/config.yaml" ]; then
  cp -f "$TMP/config/config.yaml" /opt/data/config.yaml
fi
# персонализация
if [ -f "$TMP/config/SOUL.md" ]; then
  cp -f "$TMP/config/SOUL.md" /opt/data/SOUL.md
fi
# P1: state.db* и auth.json
for f in state.db state.db-wal state.db-shm auth.json; do
  if [ -f "$TMP/config/$f" ]; then
    cp -f "$TMP/config/$f" "/opt/data/$f" 2>/dev/null || true
  fi
done

# П7 / P0: НЕ пишем .env в /opt/data/.env —
# секреты в контейнер приходят только через env_file с хоста.
# Расшифровка .env.enc / восстановление корневого .env — задача restore.ps1 на хосте.
echo "NOTE: .env / secrets are NOT restored by this Telegram/container path."
echo "NOTE: To restore secrets (.env / .env.enc) run restore.ps1 on the Windows host."

# чистим временную папку
rm -rf "$TMP"

echo "Restore OK: $(basename "$ZIP" .zip)"
echo "Tip: restart gateway if config was restored."
