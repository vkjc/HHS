---
name: wiki-llm
description: "HHS LLM Wiki (Karpathy): ingest/query/lint at /opt/data/wiki."
version: 1.0.0
author: Hermes Home Server
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [wiki, knowledge-base, memory, karpathy, notes]
    category: research
    related_skills: [llm-wiki, obsidian]
---

# wiki-llm — LLM Wiki для Hermes Home Server

Персональная база знаний по паттерну [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).
Без локальных LLM: работает через текущий провайдер Hermes (OpenRouter и т.п.).

Bundled skill `llm-wiki` — общая справка. Этот skill — **канон для HHS**: фиксированные пути и правила.

## Когда активировать

- ingest / «добавь в wiki» / «запомни в базу»
- вопрос по накопленным знаниям / проектам / людям
- lint / audit / health-check wiki
- упоминание wiki, базы знаний, `/opt/data/wiki`

## Пути (контейнер hermes-home)

```text
WIKI=/opt/data/wiki
raw (IMMUTABLE)  = /opt/data/wiki/raw/
pages (mutable)  = /opt/data/wiki/pages/
index            = /opt/data/wiki/index.md
log              = /opt/data/wiki/log.md
schema           = /opt/data/wiki/SCHEMA.md
```

На хосте Windows это же дерево: `data/wiki/` (volume → `/opt/data`).

## Три слоя

1. **raw/** — источники. **Никогда не править** после записи.
2. **pages/** — скомпилированное знание агента (`overview`, `entities/`, `concepts/`, `sources/`).
3. **SCHEMA + этот skill** — дисциплина.

## Ориентация (каждый раз перед работой)

1. Прочитать `/opt/data/wiki/SCHEMA.md`
2. Прочитать `/opt/data/wiki/index.md`
3. Просмотреть хвост `/opt/data/wiki/log.md` (последние ~20–30 строк)

Только потом — Ingest / Query / Lint.

## Ingest

1. Сохранить источник в `raw/` с именем `YYYY-MM-DD_slug.md` (или подпапка).
2. Найти существующие страницы через `index.md` и поиск по wiki.
3. Создать/обновить страницы в `pages/` (entities / concepts / sources).
4. Кросс-ссылки `[[wikilinks]]`.
5. **Обязательно** обновить `index.md` и дописать `log.md`:
   `## [YYYY-MM-DD] ingest | Title`
6. В MEMORY.md — максимум одна строка-указатель (не копировать статью).

## Query

1. Читать `index.md` → релевантные pages.
2. При необходимости: `rg` / `search_files` по `/opt/data/wiki`.
3. Ответ с цитатами страниц (`[[page]]`).
4. Ценный синтез — сохранить в `pages/` и обновить index + log.

Быстрый поиск без LLM (скрипт): `sh /opt/scripts/wiki-search.sh <query>`  
Telegram `/wikisearch` **не передаёт args** (Hermes exec) — показывает usage; поиск через NL или скрипт.

## Lint

Проверить:

- orphans (нет inbound `[[links]]`)
- broken wikilinks
- страницы вне `index.md`
- противоречия / устаревшее
- **нет секретов** в wiki

Дописать в log: `## [YYYY-MM-DD] lint | N issues`

Статус без LLM: `sh /opt/scripts/wiki-status.sh` или Telegram `/wikistatus`.

## MEMORY vs wiki

| Куда | Что |
|------|-----|
| MEMORY.md / USER.md | Горячие факты + **указатели** на wiki path / хабы |
| wiki/pages | Долгоживущее знание и синтез |
| SOUL.md | Тон и правило «есть wiki» |

Не дублировать статьи wiki в MEMORY.

## Запреты

- Править файлы в `raw/` после создания
- Класть токены, пароли, содержимое `.env`, API keys
- Раздувать MEMORY полными summaries

## Cron

Еженедельный lint (пример):

```text
hermes cron create "0 10 * * 0" --name wiki-lint --skill wiki-llm --deliver origin "Lint /opt/data/wiki per skill wiki-llm. Short report. Append log.md."
```

## Связанные команды Telegram

- `/wikistatus` — count `.md`, размер, хвост log
- `/wikisearch` — usage (args у exec quick_commands нет)
- NL: «ingest…», «что знаем про…», «lint wiki»
