# Global Search v2 (FTS/индексация) — PRD/Tech Spec — Draft

Дата: 2026-01-19
Статус: draft (для Milestone 2)

## 0) Контекст

Сейчас “глобальный поиск” фактически ограничен метаданными и marks (notes/highlights) в памяти/Hive (см. `lib/src/features/library/presentation/library_controller.dart`). Полнотекст по всему контенту библиотеки отсутствует и отмечен как следующий шаг в `STATE.md`.

В `docs/architecture_ui.md` предусмотрен `GlobalSearchScreen` с табами (Books / Notes / Quotes) и переходом в Reader “jump-to-location”.

## 1) Цели

1) **Полнотекст по всей библиотеке** (по содержимому книг) + по notes + по quotes/highlights.
2) **Быстрый UX**: debounce, быстрые ответы, устойчивость на десятках книг.
3) **Jump-to-location**: клик по результату открывает Reader в нужной книге и примерно в нужном месте.
4) **Инкрементальность**: индекс обновляется при import/delete/sync без необходимости ручного rebuild.
5) **Диагностика**: понятные ошибки индекса, кнопка “Перестроить индекс”, метрики (кол-во записей, время rebuild).

## 2) Не-цели (первый релиз Global Search v2)

- Семантический поиск (Qdrant/эмбеддинги) — позже.
- Глобальный поиск по PDF (если/когда появится) — позже.
- Идеально точный offset на каждое совпадение (символьная точность) — позже; в v2 достаточно попадать в параграф/окрестность.
- Поддержка web (Flutter web) для SQLite/FTS — явно out-of-scope, если не требуется.

## 3) Решение: storage под индекс

### Выбор: SQLite + FTS5 (рекомендовано)

**Почему сейчас (несмотря на старую заметку “не внедрять FTS” в `docs/next_stage_backlog_issues.md`):**
критерий из `STATE.md` (“FTS/индексация”) становится текущей задачей; ценность полнотекста по содержимому книг существенно выросла относительно стоимости (в проекте уже есть in-book search, anchors и стабильные тесты — базовые блоки готовы).

**Подход:** Hive остаётся источником правды, SQLite FTS — вторичный индекс.

### Альтернатива: упрощённый индекс (Hive/in-memory)

Допускается только как spike/прототип на 1 PR для UX-демо, но не как финальное решение для полнотекста по тексту книг.

## 4) Архитектура (высокоуровнево)

- `LibraryStore` (Hive) — source of truth: книги, заметки, выделения, закладки, позиции.
- `SearchIndexDb` (SQLite FTS5) — индекс: книги (параграфы/чанки) + marks (notes/highlights).
- `SearchIndexService` — API уровня приложения:
  - search по категориям,
  - rebuild,
  - инкрементальные апдейты (upsert/delete),
  - status/diagnostics.

## 5) Data model индекса

### 5.1 Общие принципы

- **Нормализация ссылки на место**: используем `Anchor` из `lib/src/core/types/anchor.dart`.
  - Для книги: `chapterHref|offset` — offset на начало параграфа/чанка.
- **Версионность схемы**: `schemaVersion` в meta-таблице.
- **Idempotency**: rebuild и upsert должны давать один и тот же результат при одинаковых входных данных.
- **Безопасность**: индекс хранит только контент книг/заметок (что и так уже локально хранится). Никаких токенов/секретов.

### 5.2 Таблицы (текущая реализация)

**Meta**
- `search_meta` (обычная таблица):
  - `id INTEGER PRIMARY KEY CHECK (id = 1)`
  - `schema_version INTEGER NOT NULL`
  - `last_rebuild_at TEXT NULL` (ISO8601)
  - `last_rebuild_ms INTEGER NULL`
  - `last_error TEXT NULL`
  - `books_rows INTEGER NULL`
  - `marks_rows INTEGER NULL`

**Books FTS**
- `fts_books` (FTS5):
  - `book_id UNINDEXED`
  - `book_title`
  - `book_author`
  - `chapter_title`
  - `content` (текст параграфа/чанка)
  - `anchor UNINDEXED` (Anchor string)
  - `chapter_href UNINDEXED`
  - `chapter_index UNINDEXED` (int)
  - `paragraph_index UNINDEXED` (int)

**Marks FTS (notes + highlights)**
- `fts_marks` (FTS5):
  - `book_id UNINDEXED`
  - `mark_id UNINDEXED`
  - `mark_type UNINDEXED` (`note` | `highlight`)
  - `anchor UNINDEXED` (Anchor string)
  - `content` (для note: `noteText + \"\\n\" + excerpt`, для highlight: `excerpt`)

**Books state (для reconcile)**
- `search_books_state` (обычная таблица):
  - `book_id TEXT PRIMARY KEY`
  - `fingerprint TEXT NOT NULL`
  - `indexed_at TEXT NULL` (ISO8601)

## 6) Извлечение текста книг (индексация)

### 6.1 Единица индексации

В v2: **параграф** как единица индексации (`1 paragraph = 1 row`).

Почему:
- anchors в проекте уже завязаны на offset в “склеенном тексте главы” (см. Reader search), поэтому offset на начало параграфа достаточно, чтобы прыгнуть в нужную область.

### 6.2 Как получить offset параграфа

Определение offset в главе:
- считаем, что “глава = title + paragraphs[]” и текст для поиска собирается конкатенацией **без разделителей** (как в `ReaderController._chapterSearchText`).
- offset параграфа = `len(title) + sum(len(prevParagraphs))`.
  - важно: если в `paragraphs[]` есть пустые/пробельные строки, они всё равно должны учитываться в `sum(len(...))` для консистентности offsets.

В v2 можно использовать упрощение:
- offset = “количество символов до начала параграфа в склеенном тексте”, без учёта визуальных отступов.
Прыжок в Reader делает оценку scroll-offset через измерения (см. `ReaderScreen._estimateAnchorScrollOffset`), поэтому нужна консистентность “символьных offsets”.

### 6.3 Кеш/производительность

- Rebuild может быть дорогим: в UI нужно состояние “Индекс строится…”.
- Инкрементальные апдейты при import/delete/sync должны быть предпочтительнее полного rebuild.

## 7) Поисковые запросы и ранжирование

### 7.1 Нормализация запроса

- trim.
- токенизация по буквам/цифрам (unicode), lower-case.
- match-expression: `token* AND token*` (prefix search).
- минимальная длина (например ≥ 2 символов) — можно добавить как UI-правило, сейчас не обязательно.

### 7.2 Ранжирование (v2)

- Использовать `bm25()` (FTS5) с весами:
  - Books: `book_title` > `chapter_title` > `content`
  - Marks: `content` (в v2 общий слой для notes/highlights)

### 7.3 Snippets

- v2: короткий snippet (±N символов) вокруг первого совпадения.
- Подсветка:
  - минимально: подсветить в UI простым `TextSpan` по найденному query (без учета stemming).
  - FTS highlight/snippet можно добавить позже, если используем raw SQL.

## 8) Инкрементальные обновления индекса

### 8.1 Триггеры (источники событий)

- Import book:
  - после успешного добавления книги в `LibraryStore` → `indexBook(bookId)`.
- Delete book:
  - после удаления записи/файла → `deleteBook(bookId)` в индексе.
- Sync:
  - после применения sync-изменений (книга добавлена/удалена/изменена) → reconcile индекса:
    - если `fingerprint` изменился → переиндексация book rows,
    - если книга исчезла → удалить rows,
    - если появилась → индексировать.

### 8.2 Стратегия reconcile

Вариант (простая, предсказуемая):
- при событии “library changed” строим множество `bookId -> fingerprint` из Hive,
- сравниваем с сохранённым snapshot в `search_meta` (или отдельной `search_books_state` таблице),
- выполняем diff.

## 9) UX: GlobalSearchScreen v2

### 9.1 Структура

- SearchField сверху + Tabs:
  - **Books** (по тексту книг),
  - **Notes**,
  - **Quotes** (highlights).
- Текущий роутинг: экран `GlobalSearchScreen` открывается из `LibraryScreen` (push route) до появления AppShell/нижней навигации.

### 9.2 Состояния

См. `docs/ui_states_and_entities.md` (GlobalSearchScreen):
- Loading: показывать прогресс (linear) при поиске.
- Empty (нет запроса): подсказка “Введите запрос…”.
- Empty (нет результатов): “Ничего не найдено”.
- Error: “Поиск недоступен” + action “Перестроить индекс”.

### 9.3 Jump-to-location

- Books hit:
  - открыть `ReaderScreen(bookId, initialAnchor: anchor)`.
- Notes/Quotes:
  - можно сохранить текущую модель (open book + jump по markId),
  - либо перейти на `initialAnchor` напрямую (если anchor доступен).

## 10) Диагностика и операции

### 10.1 Раздел диагностики

В Settings → Diagnostics:
- статус индекса: schemaVersion, lastRebuildAt, lastRebuildMs, counts, lastError.
- кнопки:
  - “Перестроить индекс”
  - “Скопировать ошибку”

### 10.2 Логи

- Все ошибки rebuild/search логируются через `Log` (редакция секретов уже есть).
- В meta хранить короткий `last_error` (без огромных stacktrace).

## 11) Тест-план (обязательный минимум)

### Unit
- normalize/escape query.
- reconcile diff (added/removed/changed fingerprints).
- anchor offset calculation for paragraphs (на фикстурах).

### DB-level
- create schema, insert sample rows, query results.
- deterministic ranking на фиксированных данных (минимальный набор).

### Widget
- GlobalSearchScreen: пустой запрос, результаты, переключение табов, error state.
- Jump-to-location: открыть Reader на anchor (smoke, без точной визуальной проверки).

### Manual (acceptance)
- Импортировать 3–5 книг → поиск по редким словам находит результаты в Books.
- Создать note/highlight → находится в Notes/Quotes.
- Удалить книгу → результаты исчезают.
- Симулировать “сломанный индекс” → “Перестроить индекс” восстанавливает.

## 12) Performance budgets (ориентиры)

- Поиск (SQL query + маппинг результатов): ≤ 50–100ms на типовом ноутбуке для `limit<=50`.
- Rebuild 10 книг средней длины: ≤ 30–90s (однократно; показывать progress/не блокировать UI).
- Индекс по объёму: допускается +20–40% от текста (ориентир).

## 13) Rollout / migration

- Если schemaVersion отличается: удалить файл индекса и rebuild.
- Все операции должны быть безопасны при частичном индексе (поиск возвращает частичные результаты, UI не падает).

## 14) Разбиение на PR (7 PR, 1 день = 1 PR)

Нотация: 1 PR = 1 задача = 1 день. Имена веток по `docs/workflow.md`.

### PR1 — Decision + Spike
**Branch:** `feature/global-search-v2-decision-spike`
**Цель:** зафиксировать решение “SQLite FTS5” и показать минимальный сквозной поток на маленьком датасете.

**Checklist**
- [x] Добавить этот документ (`docs/search_global_v2.md`) и короткое резюме решения.
- [x] Spike: минимальная SQLite БД + одна FTS таблица (например только notes/quotes).
- [x] API-черновик `SearchIndexService.search(query)` возвращает результаты (без UI-табов).

**Acceptance Criteria**
- Есть документ решения и критерии готовности.
- Прототип выдаёт стабильные результаты и не падает на пустой библиотеке.

**Test Plan**
- `flutter test` (unit на normalize query).

### PR2 — SearchIndex DB skeleton (schema + meta + status)
**Branch:** `feature/search-index-db-skeleton`
**Цель:** оформить схему, meta/status и основу сервиса индекса.

**Checklist**
- [x] Создать модуль индекса (директория/файлы по месту в проекте).
- [x] Реализовать `schemaVersion`, `search_meta`, хранение `lastError`.
- [x] `status()` + безопасное поведение при отсутствующей/битой БД (создать заново).

**Acceptance Criteria**
- `status()` работает в fresh install и после удаления файла БД.
- Ошибки индекса не валят UI (оборачиваются в понятное состояние).

**Test Plan**
- DB-level: создать schema, прочитать status.

### PR3 — Books index rebuild (chapters/paragraphs)
**Branch:** `feature/search-index-books-rebuild`
**Цель:** rebuild по содержимому книг в `fts_books`.

**Checklist**
- [x] Вынести извлечение текста книги в переиспользуемый слой (не UI).
- [x] Rebuild: пройти по книгам в `LibraryStore`, извлечь главы/параграфы, записать rows.
- [x] Считать `books_rows` и сохранять `lastRebuildAt/lastRebuildMs`.

**Acceptance Criteria**
- `rebuildAll()` индексирует библиотеку и завершается без падений.
- Повторный rebuild идемпотентен (counts/результаты совпадают).

**Test Plan**
- Unit: расчёт offset начала параграфа (в соответствии с `ReaderController._chapterSearchText`).
- DB-level: вставка/поиск по books rows.

### PR4 — Incremental updates (import/delete/sync reconcile)
**Branch:** `feature/search-index-incremental`
**Цель:** индекс поддерживается автоматически при изменениях библиотеки.

**Checklist**
- [x] `indexBook(bookId)` + `deleteBook(bookId)` (books/notes/quotes).
- [x] reconcile по `bookId -> fingerprint` (detect added/removed/changed).
- [x] Встроить вызовы в импорт/удаление книги и в конец sync-операции.

**Acceptance Criteria**
- Импортировал книгу → находится в Books табе без ручного rebuild.
- Удалил книгу → результаты исчезли.
- После синка индекс не остаётся “в рассинхроне” с библиотекой.

**Test Plan**
- Unit: reconcile diff.

### PR5 — GlobalSearchScreen v2 UI (tabs + states)
**Branch:** `feature/global-search-ui-tabs`
**Цель:** UI как в `docs/architecture_ui.md`: tabs Books/Notes/Quotes и корректные состояния.

**Checklist**
- [x] Добавить/выделить UI/контроллер глобального поиска (отдельно от `LibraryController`).
- [x] Tabs: Books / Notes / Quotes, отдельные запросы (или общий с фильтром).
- [x] Состояния: loading/empty/error + действие “Перестроить индекс”.

**Acceptance Criteria**
- UX не блокируется на вводе/переключении табов.
- Ошибка индекса отображается понятным баннером (без stack trace).

**Test Plan**
- Widget: пустой запрос, no results, переключение табов.

### PR6 — Jump-to-anchor (books hits → Reader)
**Branch:** `feature/global-search-jump-to-anchor`
**Цель:** результат из Books открывает Reader на anchor.

**Checklist**
- [x] Навигационный контракт: `ReaderScreen(bookId, initialAnchor: ...)` (или эквивалент).
- [x] Реализовать jump по anchor: chapterIndex + offset.

**Acceptance Criteria**
- Тап по результату из Books ведёт в нужную книгу и разумно позиционирует текст.

**Test Plan**
- Unit: resolve chapterIndex по chapterHref.
- Widget smoke: открыть Reader с initialAnchor не падает.

### PR7 — Diagnostics + ranking/snippets + hardening
**Branch:** `feature/search-index-diagnostics-ranking`
**Цель:** довести до “пользовательского качества”: rebuild из UI, ранжирование, сниппеты, устойчивость.

**Checklist**
- [x] Diagnostics: статус/кнопка “Перестроить индекс” + вывод lastError.
- [x] Ranking: `bm25` веса и детерминированный порядок при равных score.
- [x] Snippets: короткий текст вокруг совпадения + подсветка query в UI (минимально).

**Acceptance Criteria**
- Пользователь может восстановить индекс сам (без перезапуска/ручных действий).
- Поиск не деградирует в “рандомную выдачу” на похожих запросах.

**Test Plan**
- DB-level: ranking deterministic на фиксированных данных.
- Manual: rebuild после удаления файла индекса.

## 15) Open questions

- Нужен ли отдельный “Books by metadata” режим (title/author) или он остаётся в Library search?
- Требуется ли web поддержка? Если да — отдельная реализация (не FTS5).
- Нужен ли фоновой rebuild (Isolate) прямо сейчас или достаточно “в фоне” через Future без UI-block?

## 16) Manual Test Plan

См. `docs/manual_test_plan_milestone2.md`.
