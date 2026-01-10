# Backlog следующего этапа (после MVP0) — GitHub Issues (готовые тела)

Этот файл предназначен для **копипаста в GitHub Issues**: каждый Issue уже оформлен в одном стиле (Context / Checklist / Acceptance Criteria / Test Plan / Notes).  
Процесс: **1 issue ≈ 1 PR ≈ 1 день**.

---

## Labels (рекомендованные)
- `epic:stabilization`, `epic:active-reading`, `epic:search`, `epic:sync-ready`
- `type:feature`, `type:refactor`, `type:perf`, `type:test`, `type:docs`, `type:spike`
- `prio:P0` / `prio:P1` / `prio:P2` / `prio:P3`
- `size:S` (≤ 1 день), `size:M` (разбить на 2 issue), `size:L` (разбить обязательно)

## Milestones (предложение)
- **M1 Stabilization**
- **M2 Active Reading (Notes/Highlights/Bookmarks)**
- **M3 Search**
- **M4 Sync Readiness**

---

# EPIC 1 — Stabilization (M1)

## Issue 1 — Reader perf: замеры и выбор стратегии рендера
**Labels:** `epic:stabilization` `type:perf` `prio:P0` `size:S`  
**Suggested branch:** `perf/reader-baseline-metrics`

### Context
На больших EPUB текущий подход “всё одним деревом” почти гарантирует лаги/память. Нужно зафиксировать baseline и выбрать стратегию: **рендер по главам** или **виртуализация по чанкам**.

### Checklist
- [ ] Добавить замеры времени (логами/таймстампами):
  - [ ] import/open (до первого кадра контента)
  - [ ] unzip + parse OPF/TOC
  - [ ] build chapters (извлечение текста)
- [ ] Добавить возможность включать/выключать perf-логи (например, флаг `kDebugMode`).
- [ ] Прогнать 2–3 “тяжёлых” EPUB (большой объём текста, много глав).
- [ ] Зафиксировать решение: **chapters-as-pages** или **chunked virtual list**, с аргументами.

### Acceptance Criteria
- Есть baseline измерения (в PR description или `docs/perf.md`).
- Есть чёткое решение с критериями успеха (что улучшаем, чем меряем).

### Test Plan (manual)
1) Открыть 2–3 больших EPUB.  
2) Сравнить “время до контента” и отсутствие фризов при первом взаимодействии.

### Notes
- Если нет “тяжёлых” EPUB в репо — держать локально тестовый набор и не коммитить (или добавить в `.gitignore`).

---

## Issue 2 — Reader: lazy render по главам (убрать “вся книга одним деревом”)
**Labels:** `epic:stabilization` `type:perf` `prio:P0` `size:S`  
**Depends on:** Issue 1  
**Suggested branch:** `perf/reader-render-by-chapters`

### Context
Основной perf-риск — огромный Widget-tree. Делим рендер минимум по главам.

### Checklist
- [ ] Перейти на отображение **по главам** (каждая глава — отдельная сущность рендера).
- [ ] Навигация по TOC открывает конкретную главу (без пересборки всей книги).
- [ ] Сохранить текущие функции: TOC, переходы, восстановление позиции (где возможно).
- [ ] Не ломать Desktop split-view (если он используется).

### Acceptance Criteria
- Большие EPUB открываются без видимых “подвисаний” при скролле/переключении глав.
- Переключение глав не приводит к повторному полному парсингу книги.

### Test Plan (manual)
1) Открыть большой EPUB.  
2) 10 раз перейти между 2–3 главами через TOC.  
3) Пролистать 2–3 экрана текста в каждой главе.

### Notes
- Если решено делать “параграфы чанками”, оформить как отдельный Issue (не смешивать).

---

## Issue 3 — Reader: кешировать результат парсинга глав (in-memory)
**Labels:** `epic:stabilization` `type:perf` `prio:P0` `size:S`  
**Depends on:** Issue 2  
**Suggested branch:** `perf/reader-chapter-cache`

### Context
Повторный переход к главе не должен заново распаковывать/парсить EPUB.

### Checklist
- [ ] Добавить кеш (на время сессии чтения) для текста глав или промежуточных результатов.
- [ ] Инвалидировать кеш при закрытии книги/смене книги.
- [ ] Добавить простые логи “cache hit/miss” в debug.

### Acceptance Criteria
- При переходе туда/сюда между главами парсинг не повторяется (видно по логам / ощущению).

### Test Plan (manual)
1) Открыть книгу.  
2) Переключить главы A↔B 5–10 раз.  
3) Убедиться, что повторный парсинг не выполняется.

---

## Issue 4 — Reader: явные состояния (loading/error/retry)
**Labels:** `epic:stabilization` `type:refactor` `prio:P1` `size:S`  
**Suggested branch:** `refactor/reader-states-retry`

### Context
Ошибки чтения/парсинга должны быть управляемыми: пользователь должен видеть причину и иметь retry.

### Checklist
- [ ] Ввести единое state-машину: `loading` → `content` → `error`.
- [ ] Показать UI для `error` с кнопкой `Retry`.
- [ ] Обработать типовые ошибки: файл удалён, нет доступа, zip битый, таймаут.

### Acceptance Criteria
- Ошибка отображается понятным сообщением.
- `Retry` реально повторяет попытку и может восстановиться при временной ошибке.

### Test Plan (manual)
1) Импортировать книгу.  
2) Удалить файл книги из app storage.  
3) Открыть книгу → увидеть error → Retry → остаётся error (ожидаемо) с понятным текстом.

---

## Issue 5 — Presentation слой: ReaderController (вынести IO/парсинг из Widget)
**Labels:** `epic:stabilization` `type:refactor` `prio:P0` `size:S`  
**Suggested branch:** `refactor/reader-controller`

### Context
Сейчас UI частично выполняет IO/парсинг. Нужен слой управления состоянием (Controller/VM), чтобы:
- упростить UI;
- повысить тестируемость;
- приблизить код к целевой архитектуре.

### Checklist
- [ ] Создать `ReaderController` (или аналог) с публичным state.
- [ ] Перенести из Widget: загрузку книги, парсинг, подготовку глав, обработку ошибок.
- [ ] Обновить Reader UI: подписка на state + вызов действий контроллера.
- [ ] Покрыть контроллер unit-тестом на state transitions (минимум).

### Acceptance Criteria
- В `ReaderScreen` нет прямого `File.readAsBytes()` / распаковки zip.
- Есть unit-тест на “loading → content” и “error → retry → content/error”.

### Test Plan (manual)
1) Открыть книгу из библиотеки.  
2) Убедиться, что Reader стабильно показывает контент и TOC.

### Notes
- Конкретный state management (Riverpod/ChangeNotifier) — выбрать минимально инвазивный, но с перспективой расширения.

---

## Issue 6 — Presentation слой: LibraryController (UI без прямых вызовов store)
**Labels:** `epic:stabilization` `type:refactor` `prio:P1` `size:S`  
**Suggested branch:** `refactor/library-controller`

### Context
Библиотека уже имеет операции загрузки/поиска/удаления. UI должен стать отображающим слоем.

### Checklist
- [x] Создать `LibraryController` со state: `loading`, `items`, `filteredItems`, `error`.
- [x] Вынести: load, search, remove, clear в контроллер.
- [x] UI работает через state (и вызывает методы контроллера).

### Acceptance Criteria
- `LibraryScreen` не содержит бизнес-логики (кроме привязки к виджетам).
- Ошибки store/IO отображаются через state.

### Test Plan (manual)
1) Импортировать книгу.  
2) Поиск → результаты.  
3) Удалить книгу → исчезла из списка, повторный запуск не возвращает.

---

## Issue 7 — Тесты: заменить проверки “по строкам” на Keys
**Labels:** `epic:stabilization` `type:test` `prio:P1` `size:S`  
**Suggested branch:** `test/ui-keys`

### Context
Тесты на строках ломаются при правках локализации/текста. Нужны стабильные `Key`.

### Checklist
- [x] Проставить `Key` на критические элементы:
  - import button / open reader / toc / search / delete / notes list / bookmarks (по мере появления).
- [x] Обновить widget-tests на поиск по `Key`.

### Acceptance Criteria
- Widget-тесты не зависят от текстов на русском.

### Test Plan
- `flutter test` проходит локально и в CI.

---

## Issue 8 — Unit tests: StorageServiceImpl (copy/hash/dedup/errors)
**Labels:** `epic:stabilization` `type:test` `prio:P1` `size:S`  
**Suggested branch:** `test/storage-service`

### Context
Хранилище — критичная часть. Нужны тесты на hash/dedup/ошибки.

### Checklist
- [x] Тест “копирование в app storage”.
- [x] Тест “dedup по fingerprint (sha-256)”.
- [x] Тест “ошибка при отсутствии файла / отсутствии прав”.
- [x] Тест “верификация расширения .epub (если логика есть)” (опционально).

### Acceptance Criteria
- Минимум 3 unit-теста покрывают сценарии успеха и 1–2 сценария ошибок.

### Test Plan
- `flutter test` зелёный.

---

## Issue 9 — Docs: обновить STATE.md + data contract
**Labels:** `epic:stabilization` `type:docs` `prio:P2` `size:S`  
**Suggested branch:** `docs/update-state-data-contract`

### Context
Документация должна соответствовать реальности MVP0. Плюс — нужен контракт данных, чтобы аккуратно расширять модели (notes/highlights/bookmarks).

### Checklist
- [x] Обновить `STATE.md` под реальный статус.
- [x] Добавить `docs/data_contract.md`:
  - `LibraryEntry`
  - `ReadingPosition`
  - `Note`
  - `Highlight`
  - `Bookmark`
  - правила `id`, `updatedAt`, `anchor`

### Acceptance Criteria
- По `docs/data_contract.md` понятно, какие поля обязательны и как они эволюционируют.

---

# EPIC 2 — Active Reading: Notes/Highlights/Bookmarks (M2)

## Issue 10 — Anchors v1: формат + хелперы (serialize/parse/validate)
**Labels:** `epic:active-reading` `type:feature` `prio:P0` `size:S`  
**Suggested branch:** `feature/anchors-v1`

### Context
Нужен устойчивый минимальный anchor, чтобы привязать highlights/notes/bookmarks и уметь прыгать в место.

### Checklist
- [ ] Зафиксировать формат Anchor v1 (например): `chapterHref|offset` (+ optional fragment).
- [ ] Добавить хелперы: `Anchor.parse`, `Anchor.toString`, `Anchor.isValid`.
- [ ] Определить правила экранирования разделителя (`|`) и пустых значений.

### Acceptance Criteria
- Anchor генерируется и парсится одинаково во всех местах.
- При некорректном anchor — безопасный fail (не падать).

### Test Plan
- Unit: parse/serialize roundtrip, invalid inputs.

---

## Issue 11 — Highlights: создать highlight из выделения (минимальный UX)
**Labels:** `epic:active-reading` `type:feature` `prio:P0` `size:S`  
**Depends on:** Issue 10  
**Suggested branch:** `feature/highlights-create`

### Context
Пользователь выделяет текст → сохраняет highlight → видит в списке.

### Checklist
- [ ] Добавить контекстное меню на selection: `Highlight`.
- [ ] Сохранять сущность Highlight:
  - [ ] `id` (uuid)
  - [ ] `bookId`
  - [ ] `anchor`
  - [ ] `excerpt`
  - [ ] `createdAt`, `updatedAt`
  - [ ] `color` (optional, можно default)
- [ ] Persist: записывать в Hive через `LibraryStore`.

### Acceptance Criteria
- Highlight создаётся и сохраняется (после перезапуска остаётся).
- Нельзя создать highlight без текста/anchor (валидация).

### Test Plan (manual)
1) Открыть книгу → выделить абзац → Highlight.  
2) Закрыть/открыть приложение → highlight на месте/в списке.

### Test Plan (unit)
- `LibraryStore.addHighlight()` добавляет и сохраняет корректные поля.

---

## Issue 12 — Notes: создать note из выделения (минимальный UX)
**Labels:** `epic:active-reading` `type:feature` `prio:P0` `size:S`  
**Depends on:** Issue 10  
**Suggested branch:** `feature/notes-create`

### Context
Пользователь выделяет текст → добавляет заметку → текст заметки сохраняется.

### Checklist
- [ ] Контекстное меню selection: `Note`.
- [ ] Диалог ввода текста (минимум: multiline, кнопки Save/Cancel).
- [ ] Сохранять сущность Note:
  - [ ] `id`, `bookId`, `anchor`, `excerpt`
  - [ ] `text`
  - [ ] `createdAt`, `updatedAt`
- [ ] Persist в Hive через `LibraryStore`.

### Acceptance Criteria
- Note сохраняется и переживает перезапуск.
- Пустая note не сохраняется (валидация).

### Test Plan (manual)
1) Выделить текст → Note → ввести текст → Save.  
2) Перезапустить → note присутствует.

---

## Issue 13 — Notes & Highlights: экран списка по книге
**Labels:** `epic:active-reading` `type:feature` `prio:P0` `size:S`  
**Depends on:** Issue 11, 12  
**Suggested branch:** `feature/notes-highlights-list`

### Context
Нужен единый список по книге: notes + highlights, с фильтрами и переходом к месту.

### Checklist
- [ ] Добавить вход в список из Reader (иконка/кнопка).
- [ ] Экран/панель “Notes & Highlights”:
  - [ ] список элементов
  - [ ] фильтр: all / notes / highlights
  - [ ] сортировка: newest first
- [ ] Показать минимум: excerpt + тип + дата.

### Acceptance Criteria
- Список открывается и отображает корректные элементы текущей книги.
- Фильтры работают.

### Test Plan (manual)
1) Создать 1 highlight и 1 note.  
2) Открыть список → увидеть оба.  
3) Переключить фильтр → увидеть соответствующие элементы.

---

## Issue 14 — Jump-to-anchor: переход из списка к месту в книге
**Labels:** `epic:active-reading` `type:feature` `prio:P0` `size:S`  
**Depends on:** Issue 13  
**Suggested branch:** `feature/jump-to-anchor`

### Context
Список заметок бессмысленен без перехода к месту: tap → открыть главу и проскроллить к offset.

### Checklist
- [ ] Реализовать переход по Anchor v1:
  - [ ] открыть главу по `chapterHref`
  - [ ] приблизительно позиционировать по `offset`
- [ ] Fallback, если offset не применим: открыть главу и показать toast/snackbar “не удалось точно позиционировать”.

### Acceptance Criteria
- Переход работает минимум для 80% случаев (Anchor v1).
- При ошибке — приложение не падает, пользователь получает понятное сообщение.

### Test Plan (manual)
1) Создать note на середине главы.  
2) Открыть список → tap note → открыть главу близко к месту.

---

## Issue 15 — Notes: edit/delete + updatedAt
**Labels:** `epic:active-reading` `type:feature` `prio:P1` `size:S`  
**Suggested branch:** `feature/notes-edit-delete`

### Context
Нужны базовые CRUD операции для notes.

### Checklist
- [ ] Edit note text (диалог/экран редактирования).
- [ ] Delete note (с подтверждением).
- [ ] Обновлять `updatedAt` при edit.

### Acceptance Criteria
- Изменения видны сразу и сохраняются после перезапуска.

### Test Plan
- Manual: edit → reopen → текст изменён. delete → reopen → нет записи.
- Unit: update/delete корректно меняют Hive запись.

---

## Issue 16 — Highlights: delete / change color (optional)
**Labels:** `epic:active-reading` `type:feature` `prio:P2` `size:S`  
**Suggested branch:** `feature/highlights-edit-delete`

### Checklist
- [ ] Delete highlight (с подтверждением).
- [ ] (Optional) change color.

### Acceptance Criteria
- Удаление/смена цвета сохраняются после перезапуска.

---

## Issue 17 — Bookmarks: toggle + список bookmarks по книге
**Labels:** `epic:active-reading` `type:feature` `prio:P1` `size:S`  
**Depends on:** Issue 10, 14  
**Suggested branch:** `feature/bookmarks`

### Context
Закладка — быстрый способ вернуться к месту без выделения текста.

### Checklist
- [ ] Добавить кнопку toggle bookmark на текущей позиции.
- [ ] Хранить Bookmark: `id`, `bookId`, `anchor`, `createdAt`, `updatedAt`.
- [ ] Экран/панель списка bookmarks.
- [ ] Переход по bookmark (использовать Jump-to-anchor).

### Acceptance Criteria
- Bookmark создаётся/удаляется и переживает перезапуск.
- Переход по bookmark работает.

---

## Issue 18 — Data migration: безопасное расширение схемы Hive
**Labels:** `epic:active-reading` `type:refactor` `prio:P1` `size:S`  
**Suggested branch:** `refactor/hive-migration-compat`

### Context
Расширение моделей должно быть backward-compatible, иначе старые записи сломаются.

### Checklist
- [ ] Убедиться, что `fromMap`/`adapter` корректно обрабатывает отсутствующие поля.
- [ ] Добавить defaults (null-safe) для новых полей.
- [ ] Добавить тест чтения “старой” записи (fixture map без новых полей).

### Acceptance Criteria
- Старые записи загружаются без падений.
- Новые поля имеют ожидаемые значения по умолчанию.

---

## Issue 19 — Tests: notes/highlights/bookmarks end-to-end (минимум)
**Labels:** `epic:active-reading` `type:test` `prio:P1` `size:S`  
**Suggested branch:** `test/active-reading-e2e-min`

### Checklist
- [ ] Unit: add/update/delete note.
- [ ] Unit: add/remove highlight.
- [ ] Unit: toggle bookmark.
- [ ] Widget: создать note → появляется в списке.

### Acceptance Criteria
- Минимальный набор тестов закрывает критичный happy-path.

---

# EPIC 3 — Search (M3)

## Issue 20 — In-book search engine v1 (скан по главам)
**Labels:** `epic:search` `type:feature` `prio:P0` `size:S`  
**Suggested branch:** `feature/inbook-search-v1`

### Context
Нужен поиск внутри книги без сложного индекса на старте.

### Checklist
- [ ] Поиск строки по тексту глав (последовательный скан).
- [ ] Дебаунс ввода (например 250–400ms).
- [ ] Результат: chapter + snippet + позиция совпадения.
- [ ] Ограничить количество результатов (например top 50), чтобы не тормозить UI.

### Acceptance Criteria
- Поиск работает на типичных EPUB без заметных фризов.
- Результаты релевантны (сниппет показывает контекст).

### Test Plan
- Manual: ввести слово, которое встречается много раз → список появляется быстро.
- Unit (optional): match/snippet builder.

---

## Issue 21 — Search UI: результаты + переход к месту
**Labels:** `epic:search` `type:feature` `prio:P0` `size:S`  
**Depends on:** Issue 20, Issue 14  
**Suggested branch:** `feature/search-ui-jump`

### Context
Поиск нужен вместе с быстрым переходом к результату.

### Checklist
- [ ] UI поиска (в Reader): поле ввода + список результатов.
- [ ] Tap по результату → открыть нужную главу и позиционировать (хотя бы приблизительно).
- [ ] Состояния: empty, loading, results, error.

### Acceptance Criteria
- Tap по результату открывает контент в нужной главе.
- UI не блокируется на вводе.

---

## Issue 22 — Global search v1: библиотека + notes/highlights
**Labels:** `epic:search` `type:feature` `prio:P1` `size:S`  
**Suggested branch:** `feature/global-search-v1`

### Context
Пользователь хочет найти книгу/заметку быстро, не открывая конкретную книгу.

### Checklist
- [ ] Поиск по title/author в библиотеке.
- [ ] Поиск по `note.text` и `highlight.excerpt`.
- [ ] Результат открывает книгу (и при необходимости — список заметок/переход).

### Acceptance Criteria
- Результаты появляются быстро на библиотеке 50+ книг (или имитации).
- Поиск по заметкам действительно находит текст.

---

## Issue 23 — Spike: SQLite FTS для будущего полнотекста (опционально)
**Labels:** `epic:search` `type:spike` `prio:P2` `size:S`  
**Suggested branch:** `spike/sqlite-fts`

### Context
Если полнотекст по всему контенту станет нужен, FTS может быть лучше, чем самописные индексы.

### Checklist
- [ ] Оценить: объём/скорость/сложность интеграции.
- [ ] Набросать схему: что индексируем (главы/чанки/заметки).
- [ ] Описать план миграции данных.

### Acceptance Criteria
- Есть решение “делаем/не делаем в этом этапе” с аргументами и следующими шагами.

---

# EPIC 4 — Sync Readiness (M4)

## Issue 24 — Event Log: модель + локальное хранилище
**Labels:** `epic:sync-ready` `type:feature` `prio:P1` `size:S`  
**Suggested branch:** `feature/event-log-model`

### Context
Для синка нужен журнал изменений (event log), чтобы воспроизводить изменения на сервере и решать конфликты.

### Checklist
- [ ] Определить модель события:
  - [ ] `id`
  - [ ] `entityType`
  - [ ] `entityId`
  - [ ] `op` (add/update/delete)
  - [ ] `payload` (минимальный)
  - [ ] `createdAt`
- [ ] Хранение событий (Hive box / отдельное хранилище).
- [ ] API: addEvent, listEvents(limit), purgeEvents(olderThan) (optional).

### Acceptance Criteria
- События пишутся и читаются, порядок стабильный.

### Test Plan
- Unit: запись 3 событий → чтение возвращает в ожидаемом порядке.

---

## Issue 25 — Event Log записи: CRUD notes/highlights/bookmarks
**Labels:** `epic:sync-ready` `type:feature` `prio:P1` `size:S`  
**Depends on:** Issue 24 + EPIC 2  
**Suggested branch:** `feature/event-log-hooks-active-reading`

### Context
Каждое изменение notes/highlights/bookmarks должно логироваться.

### Checklist
- [ ] При add/update/delete note — писать событие.
- [ ] При add/delete highlight — писать событие.
- [ ] При toggle bookmark — писать событие.
- [ ] Payload минимальный, но достаточный для воспроизведения.

### Acceptance Criteria
- После серии действий список событий отражает все операции (без пропусков).

### Test Plan
- Unit: add note → update note → delete note → events count == 3, ops корректны.

---

## Issue 26 — Event Log: reading position updates (дебаунс + запись)
**Labels:** `epic:sync-ready` `type:feature` `prio:P2` `size:S`  
**Depends on:** Issue 24  
**Suggested branch:** `feature/event-log-reading-position`

### Context
Позиция чтения меняется часто. Нужен дебаунс, иначе event log раздуется.

### Checklist
- [ ] Дебаунс записи position events (например, не чаще N секунд).
- [ ] Писать событие “position updated” с anchor/offset.
- [ ] Не писать события, если позиция не изменилась существенно (optional).

### Acceptance Criteria
- При активном скролле не создаются сотни событий за минуту.

### Test Plan
- Manual: быстро скроллить → затем проверить список событий (ограниченное число).

---

## Issue 27 — Conflict policy doc (LWW и границы применения)
**Labels:** `epic:sync-ready` `type:docs` `prio:P2` `size:S`  
**Suggested branch:** `docs/conflict-policy`

### Context
Нужно заранее описать стратегию конфликтов, чтобы сервер и клиент совпадали.

### Checklist
- [ ] Описать LWW по `updatedAt`.
- [ ] Описать, какие поля участвуют в конфликте.
- [ ] Где LWW может быть недостаточен (например, merge notes) — отметить как future work.

### Acceptance Criteria
- Документ понятен: как решаются конфликты для каждой сущности.

---

## Issue 28 — DTO контракт (domain ↔ dto) для будущего API
**Labels:** `epic:sync-ready` `type:feature` `prio:P2` `size:S`  
**Suggested branch:** `feature/dto-contracts`

### Context
Чтобы синк/сервер не ломали клиент, нужны стабильные DTO + мапперы.

### Checklist
- [ ] DTO для: Note/Highlight/Bookmark/ReadingPosition/Event.
- [ ] Mapper’ы domain↔dto.
- [ ] Версионирование: `schemaVersion` (минимум).

### Acceptance Criteria
- Любая доменная сущность может быть сериализована в DTO и обратно без потерь (в рамках v1).

### Test Plan
- Unit: roundtrip serialize/deserialize для каждой DTO.

---

## Issue 29 — Debug: viewer/export event log (JSON)
**Labels:** `epic:sync-ready` `type:feature` `prio:P3` `size:S`  
**Suggested branch:** `feature/event-log-debug-export`

### Context
Для отладки синка удобно смотреть события и экспортировать их.

### Checklist
- [ ] Экран/диалог “Sync debug”: список последних N событий.
- [ ] Экспорт в JSON (clipboard или файл).

### Acceptance Criteria
- Можно быстро получить JSON-дамп событий и поделиться/проанализировать.

---

# Рекомендуемый порядок выполнения
1) **EPIC 1:** 1 → 2 → 3 → 5 → 7 → 8 → 9 → 4 → 6  
2) **EPIC 2:** 10 → 11 → 12 → 13 → 14 → 17 → 15 → 16 → 18 → 19  
3) **EPIC 3:** 20 → 21 → 22 (→ 23 опционально)  
4) **EPIC 4:** 24 → 25 → 27 → 28 → 26 → 29
