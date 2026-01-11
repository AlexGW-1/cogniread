# CogniRead — Backlog Этапов 1–2

Формат: **1 issue ≈ 1 PR ≈ 1 день**.

Факты по коду (на 2026‑01‑11):
- Notes/Highlights/Bookmarks реализованы.
- Поиск по книге реализован.
- Импорт и storage сейчас ограничены `.epub`.
- `STATE.md` и `docs/decisions.md` устарели в части фактических функций и выбора рендера.
- Закладки сейчас фактически «одна на книгу» из-за `toggleBookmark()` + `setBookmark()`.

---
## Labels (рекомендованные)
- `epic:stabilization`, `epic:docs`, `epic:formats`, `epic:active-reading`
- `type:feature`, `type:refactor`, `type:test`, `type:docs`, `type:perf`
- `prio:P0` / `prio:P1` / `prio:P2`
- `size:S` (≤ 1 день), `size:M` (разбить)

## Milestones
- **M1 Stabilization & Alignment**
- **M2 Active Reading v1.5 + Formats**

---
# EPIC 1 — Stabilization & Alignment (M1)

## Issue 1 — Docs: привести `STATE.md` и `docs/decisions.md` в соответствие с кодом
**Labels:** `epic:docs` `type:docs` `prio:P0` `size:S`  
**Suggested branch:** `docs/state-decisions-sync`

### Context
Документация сейчас расходится с реализацией (в частности, про marks, in-book search и выбор рендера). Это создаёт ложные ожидания и мешает планированию.

### Checklist
- [x] Обновить `STATE.md`: перечислить реально существующие функции, убрать неверные пункты «не сделано».
- [x] Обновить `docs/decisions.md`: зафиксировать текущий подход к рендеру (без WebView) и причины.
- [x] Пробежаться по `docs/spec_mvp.md` и убрать несоответствия (если есть).

### Acceptance Criteria
- Документы согласуются с текущим поведением приложения.
- В PR описано, какие расхождения были исправлены.

### Test Plan (manual)
1) Library → Reader → создать note/highlight → открыть список marks.
2) Поиск по книге.
3) Экспорт TOC.

---

## Issue 2 — Backlog hygiene: обновить `docs/next_stage_backlog_issues.md` (убрать выполненное)
**Labels:** `epic:docs` `type:docs` `prio:P1` `size:S`  
**Suggested branch:** `docs/backlog-refresh`

### Context
`docs/next_stage_backlog_issues.md` содержит много уже выполненного и местами дублирует реальность. Нужен один актуальный backlog, без «шума».

### Checklist
- [ ] Вынести полностью закрытые задачи в секцию «Done in MVP0» (или удалить).
- [ ] Оставить только реально актуальные задачи.
- [ ] Добавить ссылку на этот файл как «backlog для Этапов 1–2».

### Acceptance Criteria
- В файле нет задач, которые уже реализованы.
- Backlog читается как план «что делать дальше».

---

## Issue 3 — Architecture alignment: решение по слоям + чистка неиспользуемых заготовок
**Labels:** `epic:stabilization` `type:refactor` `prio:P0` `size:S`  
**Suggested branch:** `refactor/architecture-alignment`

### Context
Есть заготовки под Clean Architecture (`features/*/data|domain`), но основной функционал уже реализован через контроллеры + store. Без решения будет расти «двойной код».

### Checklist
- [ ] Зафиксировать решение (коротко в `docs/`):
  - Вариант A: остаёмся на Controller + Store до Sync MVP.
  - Вариант B: начинаем миграцию на usecase/repo, но строго по 1 сценарию за PR.
- [ ] Под выбранный вариант:
  - [ ] удалить/пометить deprecated неиспользуемые папки/классы, **или**
  - [ ] подключить 1 реальный usecase (без изменения UI) и удалить дубли.

### Acceptance Criteria
- Нет «слоёв ради слоёв» — либо они используются, либо убраны/заморожены с явной причиной.
- Тесты зелёные.

### Test Plan
- `flutter test`.

---

## Issue 4 — CI/Quality gate: `dart format` в CI + ноль предупреждений `flutter analyze`
**Labels:** `epic:stabilization` `type:refactor` `prio:P1` `size:S`  
**Suggested branch:** `chore/ci-quality-gates`

### Context
Нужно, чтобы PR не приносили «мелкий мусор» и чтобы анализатор был стабильно чистым.

### Checklist
- [ ] Исправить предупреждение `use_super_parameters` (например, `NotImplementedYetException`).
- [ ] Добавить в GitHub Actions шаг `dart format --set-exit-if-changed .`.
- [ ] Убедиться, что workflow остаётся воспроизводимым и быстрым.

### Acceptance Criteria
- `flutter analyze` без предупреждений/инфо (в рамках текущих lint правил).
- CI падает, если форматирование не соблюдено.

### Test Plan
- Прогнать CI.

---
# EPIC 2 — Active Reading v1.5 + Formats (M2)

## Issue 5 — Import formats: разрешить `.fb2`, `.fb2.zip` (и оставить `.epub`)
**Labels:** `epic:formats` `type:feature` `prio:P0` `size:S`  
**Suggested branch:** `feature/import-fb2`

### Context
Сейчас импорт и storage строго ограничены `.epub` (FilePicker + validate + StorageService). При этом reader уже умеет извлекать FB2/XML из zip‑архива. Нужно согласовать поддержку форматов на уровне импорта.

### Checklist
- [ ] В `LibraryController`: расширить `FilePicker.allowedExtensions` (минимум `epub`, `fb2`, `zip`).
- [ ] В `LibraryController._validate...`: заменить «нужен .epub» на whitelist‑валидацию (и нормальные ошибки).
- [ ] В `AppStorageService.copyToAppStorageWithHash`: разрешить `.fb2` и `.zip` (плюс корректное именование в app storage).
- [ ] В `clearLibrary()`: удалять не только `.epub`, а все поддержанные форматы.
- [ ] Тесты: добавить покрытия для новых расширений (dedup/hash/ошибки).

### Acceptance Criteria
- Можно импортировать `.fb2` и `.fb2.zip`.
- Дедупликация по хэшу работает для всех поддержанных расширений.

### Test Plan (manual)
1) Импортировать `.epub`.
2) Импортировать `.fb2`.
3) Импортировать `.fb2.zip`.
4) Импортировать один и тот же файл дважды → второй раз `alreadyExists`.

---

## Issue 6 — Reader: fallback для plain `.fb2` (не zip)
**Labels:** `epic:formats` `type:feature` `prio:P0` `size:S`  
**Depends on:** Issue 5  
**Suggested branch:** `feature/reader-fb2-plain`

### Context
`ReaderController._extractChapters` сейчас всегда пытается `ZipDecoder().decodeBytes(...)` и при ошибке бросает «Ошибка парсинга EPUB». Для plain `.fb2` это гарантированная ошибка.

### Checklist
- [ ] В `_extractChapters`: если zip‑декод не удался — пробовать XML‑парсинг:
  - [ ] попытка UTF‑8,
  - [ ] fallback по эвристике (например, latin1/Windows‑1251) — достаточно для MVP.
  - [ ] `XmlDocument.parse(decoded)`.
- [ ] Сконструировать главы через существующий `_chaptersFromFb2(...)`.
- [ ] Сконструировать TOC для FB2 (минимум generated) и сохранить в `LibraryEntry`.
- [ ] Сообщения об ошибках: различать «битый zip» и «битый xml».

### Acceptance Criteria
- Plain `.fb2` открывается и отображается.
- Есть оглавление и переходы по нему.

### Test Plan
- Manual: импортировать и открыть plain `.fb2`, перейти 3–5 секций через TOC.
- Unit: тест на извлечение глав из fb2 bytes (fixture).

---
