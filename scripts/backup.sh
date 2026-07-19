#!/bin/sh
# Safe backup for live Hermes data -> /opt/backups/backup-YYYY-MM-DD-HHmmss.zip

TS=$(date +%Y-%m-%d-%H%M%S)
BACKUP_DIR="/opt/backups"
ARCHIVE="$BACKUP_DIR/backup-$TS.zip"
TMP=$(mktemp -d)

copy_files() {
  src="$1"
  dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  find "$src" -type f 2>/dev/null | while IFS= read -r file; do
    rel="${file#$src/}"
    target="$dst/$rel"
    mkdir -p "$(dirname "$target")"
    cp -f "$file" "$target" 2>/dev/null || true
  done
}

mkdir -p "$TMP/memory" "$TMP/config" "$TMP/logs"

copy_files /opt/data/memories "$TMP/memory"
copy_files /opt/data/logs "$TMP/logs"

for f in config.yaml .env SOUL.md; do
  if [ -f "/opt/data/$f" ]; then
    cp -f "/opt/data/$f" "$TMP/config/" 2>/dev/null || true
  fi
done

mkdir -p "$BACKUP_DIR"

python3 <<PY
import os
import zipfile
from pathlib import Path

tmp = Path("$TMP")
archive = Path("$ARCHIVE")

with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
    for folder in ("memory", "config", "logs"):
        base = tmp / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file():
                zf.write(path, path.relative_to(tmp).as_posix())

print(f"Backup created: {archive}")
print(archive.name)
PY

status=$?
rm -rf "$TMP"

if [ "$status" -ne 0 ]; then
  echo "Backup failed" >&2
  exit 1
fi

count=0
for old in $(ls -1t "$BACKUP_DIR"/backup-*.zip 2>/dev/null); do
  count=$((count + 1))
  if [ "$count" -gt 30 ]; then
    rm -f "$old"
  fi
done
