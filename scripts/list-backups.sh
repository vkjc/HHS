#!/bin/sh
# List backups (newest first, numbered)

BACKUP_DIR="/opt/backups"
n=0

for f in $(ls -1t "$BACKUP_DIR"/backup-*.zip 2>/dev/null); do
  n=$((n + 1))
  echo "$n"
  basename "$f" .zip
  echo ""
done

if [ "$n" -eq 0 ]; then
  echo "No backups found."
  exit 1
fi

echo "Restore: /restore1 (newest), /restore2, /restore3 ..."
