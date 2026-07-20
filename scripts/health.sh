#!/bin/sh
# Ф1: /health — краткий отчёт о состоянии сервера для Telegram

# имя контейнера / хостнейм
HOST=$(hostname 2>/dev/null || echo hermes)

# жив ли процесс gateway
if pgrep -f 'hermes gateway' >/dev/null 2>&1; then
  GW="OK"
else
  GW="DOWN"
fi

# свободное место на томе данных (ГБ)
FREE_GB=$(df -BG /opt/data 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
[ -z "$FREE_GB" ] && FREE_GB="?"

# сколько архивов лежит в /opt/backups
BCOUNT=$(ls -1 /opt/backups/backup-*.zip 2>/dev/null | wc -l | tr -d ' ')

# имя самого свежего бэкапа
LAST=$(ls -1t /opt/backups/backup-*.zip 2>/dev/null | head -n 1)
if [ -n "$LAST" ]; then
  LAST=$(basename "$LAST")
else
  LAST="none"
fi

# модель из config.yaml (строка default:)
MODEL=$(grep -E '^\s*default:' /opt/data/config.yaml 2>/dev/null | head -n 1 | sed 's/.*default:[[:space:]]*//')
[ -z "$MODEL" ] && MODEL="unknown"

# uptime контейнера (если есть /proc/uptime)
UP=$(awk '{printf "%dd %dh", int($1/86400), int(($1%86400)/3600)}' /proc/uptime 2>/dev/null)
[ -z "$UP" ] && UP="?"

# печатаем отчёт (Hermes отправит его в чат как stdout exec)
echo "Hermes health ($HOST)"
echo "gateway: $GW"
echo "uptime: $UP"
echo "disk free: ${FREE_GB}G"
echo "backups: $BCOUNT (last: $LAST)"
echo "model: $MODEL"
