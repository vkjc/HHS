#!/bin/sh
# /wikisearch — поиск по wiki (rg или grep -R)
# Внимание: Hermes exec quick_commands НЕ передают args → без аргументов показываем usage.

# корень wiki
WIKI="/opt/data/wiki"
# запрос = все аргументы командной строки
QUERY="$*"

# без запроса — usage (типичный путь из Telegram /wikisearch)
if [ -z "$QUERY" ]; then
  echo "Usage: /wikisearch <query>"
  echo "Note: Telegram exec quick_commands do not pass args."
  echo "Use natural language (agent + skill wiki-llm) or:"
  echo "  docker exec hermes-home sh /opt/scripts/wiki-search.sh <query>"
  exit 0
fi

# wiki должна существовать
if [ ! -d "$WIKI" ]; then
  echo "Wiki missing: $WIKI"
  exit 1
fi

# предпочитаем ripgrep, иначе grep -R
if command -v rg >/dev/null 2>&1; then
  # поиск по md, максимум 40 строк, номера строк
  rg -n --glob '*.md' -m 40 -- "$QUERY" "$WIKI" || true
else
  # fallback: рекурсивный grep
  grep -R -n -I --include='*.md' -m 40 -- "$QUERY" "$WIKI" 2>/dev/null || true
fi
