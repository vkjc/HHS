#!/bin/sh
# Restore backup by number (1=newest). Usage: restore.sh [N]

NUM=${1:-1}
BACKUP_DIR="/opt/backups"
TMP=$(mktemp -d)

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

ZIP=$(pick_file)
if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
  echo "Invalid backup number: $NUM" >&2
  rm -rf "$TMP"
  exit 1
fi

python3 <<PY
import zipfile
from pathlib import Path

zipfile.ZipFile("$ZIP").extractall("$TMP")
print("Extracted:", "$ZIP")
PY

if [ -d "$TMP/memory" ]; then
  mkdir -p /opt/data/memories
  cp -a "$TMP/memory/." /opt/data/memories/ 2>/dev/null || true
fi
if [ -d "$TMP/logs" ]; then
  mkdir -p /opt/data/logs
  cp -a "$TMP/logs/." /opt/data/logs/ 2>/dev/null || true
fi
if [ -f "$TMP/config/config.yaml" ]; then
  cp -f "$TMP/config/config.yaml" /opt/data/config.yaml
fi
if [ -f "$TMP/config/.env" ]; then
  cp -f "$TMP/config/.env" /opt/data/.env
fi
if [ -f "$TMP/config/SOUL.md" ]; then
  cp -f "$TMP/config/SOUL.md" /opt/data/SOUL.md
fi

rm -rf "$TMP"

echo "Restore OK: $(basename "$ZIP" .zip)"
echo "Tip: restart gateway if config was restored."
