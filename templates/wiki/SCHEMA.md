# Wiki Schema (Hermes Home Server)

## Domain
Персональная база знаний домашнего сервера Hermes (паттерн LLM Wiki Карпаты).

## Paths (в контейнере)
- Корень: `/opt/data/wiki`
- Сырьё (IMMUTABLE): `/opt/data/wiki/raw/`
- Страницы (mutable): `/opt/data/wiki/pages/`
- Каталог: `/opt/data/wiki/index.md`
- Журнал: `/opt/data/wiki/log.md`
- Skill: `wiki-llm` → `/opt/data/skills/research/wiki-llm/SKILL.md`

## Layers
1. **raw/** — источники; агент только читает, никогда не правит.
2. **pages/** — скомпилированное знание; агент пишет и обновляет.
3. **SCHEMA.md + skill** — правила дисциплины.

## Operations
- **Ingest** — положить источник в `raw/`, обновить pages + index + log.
- **Query** — читать index → pages; ценный ответ можно сохранить в pages.
- **Lint** — orphans, broken links, дыры в index, устаревшее.

## Conventions
- Имена файлов: lowercase, hyphens (`my-topic.md`).
- Ссылки: `[[wikilinks]]`.
- После каждого ingest — обновить `index.md` и дописать `log.md`.
- **Секреты запрещены** (токены, `.env`, пароли) — никогда не писать в wiki.
- MEMORY.md — только указатели на wiki, не копии статей.

## Cron lint
Еженедельный job через Hermes cron (см. TECHNICAL_SPEC / skill).
Если job ещё нет — создать командой:

```text
hermes cron create "0 10 * * 0" --name wiki-lint --skill wiki-llm --deliver origin "Lint wiki at /opt/data/wiki per skill wiki-llm. Short report. Append log.md."
```
