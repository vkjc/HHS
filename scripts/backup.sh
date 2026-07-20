#!/bin/sh
# Быстрый бэкап живых данных Hermes -> /opt/backups/backup-YYYY-MM-DD-HHmmss.zip
#
# Hermes quick_commands: timeout ЖЁСТКО 30s (asyncio.wait_for), в config.yaml НЕ настраивается.
# Узкое место на Docker Desktop/Windows: сотни мелких файлов skills на bind-mount (~30s).
# Для Telegram: BACKUP_SKIP_SKILLS=1 (см. quick_commands). Полный бэкап — host backup.ps1.

# метка времени для имени архива
TS=$(date +%Y-%m-%d-%H%M%S)
# каталог с готовыми архивами (смонтирован с хоста)
BACKUP_DIR="/opt/backups"
# полный путь к новому zip
ARCHIVE="$BACKUP_DIR/backup-$TS.zip"
# временная папка только для .env / .env.enc
TMP=$(mktemp -d)

# П5: сколько архивов хранить (из .env контейнера, иначе 30)
RETENTION=${BACKUP_RETENTION:-30}

# Telegram-путь: не класть skills (много мелких файлов → >30s на bind-mount)
SKIP_SKILLS=${BACKUP_SKIP_SKILLS:-0}

# каталог бэкапов на хосте должен существовать
mkdir -p "$BACKUP_DIR"

# --- собираем .env для архива из окружения контейнера ---
ENV_OUT="$TMP/.env"
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

# путь к файлу .env внутри zip
ENV_ZIP_SRC="$ENV_OUT"
# имя файла внутри zip
ENV_ZIP_NAME="config/.env"

# П12: если задан BACKUP_PASSWORD — шифруем .env перед упаковкой
if [ -n "$BACKUP_PASSWORD" ] && [ -f "$ENV_OUT" ]; then
  # P2: пароль через файл (-pass file:), не pass: в cmdline
  PASSFILE=$(mktemp)
  # права только владельцу
  chmod 600 "$PASSFILE"
  # пишем пароль без лишнего перевода строки
  printf '%s' "$BACKUP_PASSWORD" > "$PASSFILE"
  # шифруем openssl AES-256-CBC
  openssl enc -aes-256-cbc -salt -pbkdf2 -in "$ENV_OUT" -out "$TMP/.env.enc" -pass "file:$PASSFILE" 2>/dev/null
  # сразу удаляем файл с паролем
  rm -f "$PASSFILE"
  # если шифрование удалось — в архив кладём .env.enc
  if [ -f "$TMP/.env.enc" ]; then
    ENV_ZIP_SRC="$TMP/.env.enc"
    ENV_ZIP_NAME="config/.env.enc"
    # открытый .env больше не нужен
    rm -f "$ENV_OUT"
  fi
fi

# упаковываем напрямую из /opt/data (без медленного пофайлового copy в TMP)
# compresslevel=1 — быстрее обычного DEFLATED
python3 <<PY
import zipfile
from pathlib import Path

# путь к итоговому архиву
archive = Path("$ARCHIVE")
# откуда брать .env / .env.enc
env_src = Path("$ENV_ZIP_SRC")
# как назвать .env внутри zip
env_name = "$ENV_ZIP_NAME"
# пропускать skills? (Telegram quick command)
skip_skills = "$SKIP_SKILLS" in ("1", "true", "yes", "YES")

# папки data → префикс внутри zip
folders = [
    ("memory", Path("/opt/data/memories")),
    ("logs", Path("/opt/data/logs")),
    ("sessions", Path("/opt/data/sessions")),
    ("cron", Path("/opt/data/cron")),
    # wiki всегда в архиве (даже при BACKUP_SKIP_SKILLS)
    ("wiki", Path("/opt/data/wiki")),
]
# skills только в полном бэкапе (не Telegram)
if not skip_skills:
    folders.append(("skills", Path("/opt/data/skills")))

# одиночные файлы → config/
config_files = (
    "config.yaml",
    "SOUL.md",
    "state.db",
    "state.db-wal",
    "state.db-shm",
    "auth.json",
)

# быстрое сжатие
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as zf:
    # деревья каталогов — читаем с диска напрямую
    for prefix, base in folders:
        # папки может не быть — пропускаем
        if not base.is_dir():
            continue
        # все обычные файлы
        for path in base.rglob("*"):
            if path.is_file():
                # путь внутри zip
                arc = f"{prefix}/{path.relative_to(base).as_posix()}"
                zf.write(path, arc)

    # конфиги и state.db*
    data = Path("/opt/data")
    for name in config_files:
        path = data / name
        if path.is_file():
            zf.write(path, f"config/{name}")

    # .env или .env.enc
    if env_src.is_file():
        zf.write(env_src, env_name)

# печатаем результат для Telegram/логов
print(f"Backup created: {archive}")
if skip_skills:
    print("(skills skipped for speed — full backup: host backup.ps1)")
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

# P1: зеркало — копируем zip, если BACKUP_MIRROR_DIR доступен из контейнера
if [ -n "$BACKUP_MIRROR_DIR" ]; then
  if [ -d "$BACKUP_MIRROR_DIR" ]; then
    cp -f "$ARCHIVE" "$BACKUP_MIRROR_DIR/" 2>/dev/null && echo "Mirrored to $BACKUP_MIRROR_DIR" || echo "Mirror copy failed: $BACKUP_MIRROR_DIR"
  else
    echo "BACKUP_MIRROR_DIR set but not accessible in container ($BACKUP_MIRROR_DIR) — skip mirror (use host New-HermesBackup for Windows paths)."
  fi
fi
