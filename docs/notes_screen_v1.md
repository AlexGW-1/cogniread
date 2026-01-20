# NotesScreen v1 — PRD/Tech Spec

Дата: 2026-01-20  
Статус: draft (Milestone 2+)

## 0) Контекст

В проекте уже реализованы:
- `Note` и `Highlight` внутри `LibraryEntry` (Hive) + синк через `EventLog` (file-based sync).
- UI “Заметки и выделения” внутри Reader (по текущей книге).

Цель этого документа — описать “Заметки” как **глобальный раздел** по всей библиотеке:
единый список заметок + выделений + “произвольные заметки без книги”.

## 1) Цели (v1)

1) В разделе “Заметки” показывать **заметки + выделения** вместе (как в Reader).
2) **Поиск** по тексту/выдержке прямо в этом разделе.
3) Основной вид: **лента** (последние сверху) + переключение **группировки по книгам**.
4) **Массовые действия** уже в первой версии: выбор элементов → экспорт/удаление + фильтр по цветам.
5) **Произвольные заметки без привязки к книгам** (создание/редактирование/удаление).
6) Произвольные заметки **участвуют в синхронизации** (через events).
7) Экспорт поддерживает **оба формата**: `JSON` + `Markdown` (одним действием).

## 2) Не-цели (v1)

- Теги/папки/умные коллекции.
- Публичный шаринг, облачные интеграции экспорта.
- Глобальный полнотекст по контенту книг (это отдельный Epic: `docs/search_global_v2.md`).
- “Концепты”/AI обработка.

## 3) UX

### 3.1 Основной экран

Верхняя панель:
- SearchField (по тексту noteText/excerpt).
- Переключатель вида: `Лента` ↔ `По книгам`.
- Фильтры:
  - Type: `Все` / `Заметки` / `Выделения` / `Без книги`
  - Colors: multi-select (chips).

Список:
- Элемент показывает:
  - цвет (swatch),
  - excerpt/snippet,
  - подпись: тип + дата + (для book-bound) название книги,
  - для Note дополнительно отображать `noteText` (если есть) в preview (1–2 строки).

Навигация:
- Tap по Note/Highlight (с bookId + anchor) → открыть Reader в этой книге и прыгнуть к anchor.
- Tap по “без книги” → открыть редактор заметки.

### 3.2 Выбор и массовые действия

Selection mode:
- Включается долгим тапом (mobile) / кнопкой “Выбрать” (desktop).
- В selection mode элементы получают чекбокс.

Действия (только для выбранных):
- Delete (с подтверждением).
- Export (одним действием выгружает zip с двумя файлами: `notes.json` + `notes.md`).

### 3.3 Добавление заметки без книги

CTA:
- FAB “+” на mobile в разделе “Заметки”.
- Кнопка “+” в тулбаре панели на desktop.

Редактор:
- multiline text,
- выбор цвета (из набора как в Reader),
- Save.

## 4) Data model

### 4.1 Существующие сущности

- `Note` (book-bound): `noteText + excerpt + anchor + color + createdAt/updatedAt`.
- `Highlight` (book-bound): `excerpt + anchor + color + createdAt/updatedAt`.

### 4.2 Новая сущность: FreeNote

Отдельная сущность, не часть `LibraryEntry`.

Поля:
- `id: String`
- `text: String`
- `color: String`
- `createdAt: DateTime`
- `updatedAt: DateTime`

Хранилище:
- Hive box `free_notes`.

## 5) Sync (file-based, events)

### 5.1 EntityType

Добавить новый `entityType = "free_note"` в `EventLogEntry`.

Операции:
- `op: "add" | "update" | "delete"`

Payload:
- `id`
- `text`
- `color`
- `createdAt`
- `updatedAt`

### 5.2 Conflict policy

LWW по `updatedAt` (fallback: `event.createdAt`), аналогично `note/highlight`:
- delete применяется только если incoming обновление новее текущего.
- update/add применяется только если incoming новее текущего.

## 6) Export

Один action “Export selected” создаёт `zip`:
- `notes.json` — список выбранных элементов с метаданными.
- `notes.md` — человекочитаемый экспорт тех же данных.

Рекомендуемая структура JSON:
```json
{
  "generatedAt": "2026-01-20T12:00:00Z",
  "items": [
    {
      "type": "note|highlight|free_note",
      "id": "…",
      "bookId": "…",
      "bookTitle": "…",
      "bookAuthor": "…",
      "anchor": "chapterHref|offset",
      "excerpt": "…",
      "noteText": "…",
      "text": "…",
      "color": "yellow",
      "createdAt": "…",
      "updatedAt": "…"
    }
  ]
}
```

## 7) Минимальный DoD (v1)

- Раздел “Заметки” не placeholder на desktop+mobile.
- Поиск/фильтры/группировка работают.
- Selection mode + bulk delete + export (zip: json+md) работают.
- Free notes: create/edit/delete + sync (apply remote) работают.
- Добавлены 2 дополнительных цвета (единый список цветов с Reader).

