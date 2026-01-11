# Sync Gateway Storage (Draft v0.1)

Цель: минимальные таблицы и индексы для хранения event log и состояния чтения.

---
## Таблица: `event_log`

**Назначение:** хранение событий синхронизации.

**Поля:**
- `id` (uuid, PK) — уникальный id события.
- `user_id` (uuid, index) — владелец события.
- `device_id` (uuid, index) — источник события.
- `entity_type` (text, index) — `note|highlight|bookmark|reading_position`.
- `entity_id` (text, index) — id сущности или `bookId`.
- `op` (text) — `add|update|delete`.
- `payload` (jsonb) — минимальный payload.
- `created_at` (timestamptz, index) — момент генерации события.
- `schema_version` (int) — версия схемы payload.

**Индексы:**
- `(user_id, created_at)` — выборка событий по пользователю.
- `(user_id, entity_type, entity_id)` — фильтрация для idempotency.

---
## Таблица: `reading_position`

**Назначение:** быстрый доступ к текущей позиции чтения.

**Поля:**
- `user_id` (uuid, PK)
- `book_id` (text, PK)
- `chapter_href` (text, nullable)
- `anchor` (text, nullable)
- `offset` (int, nullable)
- `updated_at` (timestamptz)

**Индексы:**
- `(user_id, updated_at)`

---
## Таблица: `sync_cursor`

**Назначение:** хранение прогресса синхронизации по устройствам.

**Поля:**
- `user_id` (uuid, PK)
- `device_id` (uuid, PK)
- `last_cursor` (text)
- `updated_at` (timestamptz)

---
## Миграции (минимум)

1) `event_log` + индексы.  
2) `reading_position`.  
3) `sync_cursor`.

---
## Примечания
- `payload` содержит `updatedAt` для LWW.
- Дедупликация: уникальность `(user_id, id)` достаточно, конфликты — 409.  
- Идемпотентность: повторный `id` не меняет состояние.
