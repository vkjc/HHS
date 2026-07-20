#!/bin/sh
# Ф3: /sendbackup — создать бэкап и отправить zip владельцу в Telegram (sendDocument)

# токен бота из окружения
TOKEN="$TELEGRAM_BOT_TOKEN"
# первый разрешённый пользователь = владелец
CHAT_ID=$(echo "$TELEGRAM_ALLOWED_USERS" | cut -d, -f1 | tr -d ' ')

# без токена/чата отправлять некуда
if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "TELEGRAM_BOT_TOKEN / TELEGRAM_ALLOWED_USERS not set" >&2
  exit 1
fi

# свежий бэкап для Telegram: без skills (лимит quick_commands 30s + bind-mount)
echo "Creating backup..."
OUT=$(BACKUP_SKIP_SKILLS=1 sh /opt/scripts/backup.sh)
# последняя строка вывода backup.sh — имя файла
NAME=$(echo "$OUT" | tail -n 1)
ZIP="/opt/backups/$NAME"

# проверяем, что архив на месте
if [ ! -f "$ZIP" ]; then
  echo "Backup file not found: $ZIP" >&2
  exit 1
fi

# лимит Telegram Bot API для sendDocument — 50 МБ
SIZE=$(wc -c < "$ZIP" | tr -d ' ')
MAX=$((50 * 1024 * 1024))
if [ "$SIZE" -gt "$MAX" ]; then
  echo "Backup too large for Telegram ($SIZE bytes > 50MB). Use BACKUP_MIRROR_DIR." >&2
  exit 1
fi

echo "Sending $NAME to Telegram..."

# экспортируем для python
export TOKEN CHAT_ID ZIP NAME

# отправляем документ через Bot API (python есть в образе)
python3 <<'PY'
import json
import os
import urllib.request
import urllib.error

# читаем параметры из окружения
token = os.environ["TOKEN"]
chat_id = os.environ["CHAT_ID"]
zip_path = os.environ["ZIP"]
name = os.environ["NAME"]

# URL метода sendDocument
url = "https://api.telegram.org/bot%s/sendDocument" % token

# multipart boundary
boundary = "----HermesBoundary7MA4YWxkTrZu0gW"
# читаем zip целиком
with open(zip_path, "rb") as f:
    file_data = f.read()

# собираем multipart тело
chunks = []
# поле chat_id
chunks.append(("--%s\r\n" % boundary).encode())
chunks.append(b'Content-Disposition: form-data; name="chat_id"\r\n\r\n')
chunks.append(("%s\r\n" % chat_id).encode())
# поле document (файл)
chunks.append(("--%s\r\n" % boundary).encode())
chunks.append(('Content-Disposition: form-data; name="document"; filename="%s"\r\n' % name).encode())
chunks.append(b"Content-Type: application/zip\r\n\r\n")
chunks.append(file_data)
chunks.append(("\r\n--%s--\r\n" % boundary).encode())
body = b"".join(chunks)

# POST-запрос
req = urllib.request.Request(url, data=body, method="POST")
req.add_header("Content-Type", "multipart/form-data; boundary=%s" % boundary)

try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode())
    if data.get("ok"):
        print("Sent: %s" % name)
    else:
        print("Telegram error:", data, flush=True)
        raise SystemExit(1)
except urllib.error.HTTPError as e:
    print("HTTP error:", e.read().decode(errors="replace"), flush=True)
    raise SystemExit(1)
PY
