#!/bin/sh
# /wikistatus — краткий статус LLM Wiki без LLM

# корень wiki в контейнере
WIKI="/opt/data/wiki"

# если каталога нет — Missing
if [ ! -d "$WIKI" ]; then
  echo "Wiki: Missing"
  echo "path: $WIKI"
  exit 0
fi

# число markdown-файлов
MD_COUNT=$(find "$WIKI" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
# размер каталога (человекочитаемо)
SIZE=$(du -sh "$WIKI" 2>/dev/null | awk '{print $1}')
[ -z "$SIZE" ] && SIZE="?"

# печатаем сводку
echo "Wiki: OK"
echo "path: $WIKI"
echo "md files: $MD_COUNT"
echo "size: $SIZE"

# хвост журнала, если есть
if [ -f "$WIKI/log.md" ]; then
  echo "--- last log lines ---"
  # последние 8 строк log.md
  tail -n 8 "$WIKI/log.md"
else
  echo "log.md: missing"
fi
